package openbaocsi

import "github.com/homelab-selfuryon/platform-components/schema"

// The OpenBao provider for the Secrets Store CSI driver: a DaemonSet on every node that the
// driver calls over a unix socket in a host path. The OpenBao server itself is `openbao`.
//
// The provider talks TLS to OpenBao and validates it with the internal CA: the CA certificate comes
// from a cert-manager Certificate whose Secret (`openbao-ca`, key `ca.crt`) is mounted into the pod.
#OpenBaoCSI: {
	#cluster: schema.#Cluster
	#ref:     schema.#Ref

	component: schema.#Component & {
		name:        "openbao-csi-provider"
		description: "OpenBao provider for the Secrets Store CSI driver."
		namespace:   "openbao-csi-provider-system"
		set:         "platform"
		dependsOn:   ["secrets-store-csi-driver", "internal-ca"]
		psa: {
			level:  "privileged"
			reason: "The provider DaemonSet shares a host path with the CSI driver for its socket."
		}

		chart: schema.#Chart & {
			kind:        "helm"
			url:         "https://openbao.github.io/openbao-helm"
			name:        "openbao"
			version:     #ref.version
			releaseName: "openbao-csi-provider"
		}
		values: {
			fullnameOverride: "openbao-csi-provider"
			global: externalBaoAddr: "https://openbao.openbao-system.svc:8200"
			server: enabled:         false
			injector: enabled:       false
			ui: enabled:             false
			csi: {
				enabled:      true
				volumes:      [{name: "openbao-ca", secret: secretName: "openbao-ca"}]
				volumeMounts: [{name: "openbao-ca", mountPath: "/openbao/tls", readOnly: true}]
				daemonSet: providersDir: "/var/run/secrets-store-csi-providers"
			}
		}

		// Only ca.crt is used.
		manifests: scoped: "openbao-csi-provider-system": certificate: "openbao-ca": spec: {
			secretName: "openbao-ca"
			commonName: "openbao-csi-provider"
			duration:   "2160h"
			usages:     ["client auth", "digital signature"]
			privateKey: {algorithm: "ECDSA", size: 256, rotationPolicy: "Always"}
			issuerRef:  {name: "internal-ca", kind: "ClusterIssuer", group: "cert-manager.io"}
		}

		network: {
			ingress: [schema.Net.sameNamespaceIn]
			egress: [
				schema.Net.apiserverOut,
				{
					toEndpoints: [{matchLabels: {"k8s:io.kubernetes.pod.namespace": "openbao-system"}}]
					toPorts:     [{ports: [{port: "8200", protocol: "TCP"}]}]
				},
			]
		}

		whitelist: [
			schema.#ClusterRole & {names: ["openbao-csi-provider-csi-provider-clusterrole"]},
			schema.#ClusterRoleBinding & {
				names: [
					"openbao-csi-provider-system-openbao-csi-provider-csi-provider-clusterrolebinding",
					"openbao-csi-provider-system-openbao-csi-provider-server-binding",
				]
				bind: ["system:auth-delegator"]
			},
		]
	}
}
