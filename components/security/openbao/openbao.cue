package openbao

import "github.com/homelab-selfuryon/platform-components/schema"

#namespace: "openbao-system"

// OpenBao: the platform's secret store. One raft node on local-path, TLS from the internal CA,
// auto-unsealed with a static seal.
//
// The seal key is the Secret `openbao-seal-key` (key `key`, 32 random bytes as 64 hex characters)
// that is created by hand at bootstrap from the break-glass bundle: it is never in git. Lose it
// and the data is gone: keep an offline copy (docs/bootstrap.md).
//
// Kubernetes auth, mounts, policies and roles are configured by platform-terraform/openbao, not
// here. The CSI provider (the node-level part) is its own component, `openbao-csi-provider`, so
// that this namespace needs no host paths and stays Pod Security `restricted`.
#OpenBao: {
	#cluster: schema.#Cluster
	#ref:     schema.#Ref

	let _tls = "/openbao/userconfig/openbao-tls"
	let _seal = "/openbao/userconfig/openbao-seal-key"

	component: schema.#Component & {
		name:        "openbao"
		description: "OpenBao: secret store (raft, static seal, TLS from the internal CA)."
		namespace:   #namespace
		set:         "platform"
		dependsOn:   ["internal-ca", "local-path-provisioner"]

		chart: schema.#Chart & {
			kind:    "helm"
			url:     "https://openbao.github.io/openbao-helm"
			name:    "openbao"
			version: #ref.version
		}
		values: {
			global: tlsDisable: false
			injector: enabled:  false
			csi: enabled:       false
			ui: enabled:        false
			server: {
				enabled: true
				// BAO_ADDR comes from the chart (https with TLS on); setting it again duplicates the
				// env entry, which server-side apply rejects.
				extraEnvironmentVars: BAO_CACERT: "\(_tls)/ca.crt"
				extraVolumes: [
					{type: "secret", name: "openbao-tls"},
					{type: "secret", name: "openbao-seal-key"},
				]
				dataStorage: {
					enabled:      true
					size:         "10Gi"
					storageClass: "local-path"
				}
				auditStorage: enabled: false
				// Pod Security restricted: the chart's defaults already drop privileges; the seccomp
				// profile is part of them.
				ha: {
					enabled:  true
					replicas: 1
					raft: {
						enabled:   true
						setNodeId: true
						config: """
							ui = false
							disable_mlock = true

							listener "tcp" {
							  address         = "[::]:8200"
							  cluster_address = "[::]:8201"
							  tls_cert_file   = "\(_tls)/tls.crt"
							  tls_key_file    = "\(_tls)/tls.key"
							}

							storage "raft" {
							  path = "/openbao/data"
							}

							seal "static" {
							  current_key_id = "\(#cluster.name)-1"
							  current_key    = "file://\(_seal)/key"
							}

							service_registration "kubernetes" {}
							"""
					}
				}
			}
		}

		manifests: scoped: (#namespace): certificate: "openbao-tls": spec: {
			secretName: "openbao-tls"
			duration:   "2160h"
			dnsNames: [
				"openbao",
				"openbao.\(#namespace)",
				"openbao.\(#namespace).svc",
				"openbao.\(#namespace).svc.cluster.local",
				"openbao-active.\(#namespace).svc",
				"*.openbao-internal",
				"localhost",
			]
			ipAddresses: ["127.0.0.1", "::1"]
			usages:      ["server auth", "digital signature", "key encipherment"]
			privateKey:  {algorithm: "ECDSA", size: 256, rotationPolicy: "Always"}
			issuerRef:   {name: "internal-ca", kind: "ClusterIssuer", group: "cert-manager.io"}
		}

		// Kubernetes auth with bound_service_account_namespace_selector (preview roles in
		// platform-terraform/openbao) makes OpenBao read the labels of namespaces.
		manifests: global: clusterRole: "openbao-namespace-reader": rules: [{
			apiGroups: [""]
			resources: ["namespaces"]
			verbs:     ["get", "list"]
		}]
		manifests: global: clusterRoleBinding: "openbao-namespace-reader": {
			roleRef:  {apiGroup: "rbac.authorization.k8s.io", kind: "ClusterRole", name: "openbao-namespace-reader"}
			subjects: [{kind: "ServiceAccount", name: "openbao", namespace: #namespace}]
		}

		network: {
			ingress: [
				schema.Net.sameNamespaceIn,
				// Secrets Store CSI provider (its own namespace) and Kubernetes auth clients.
				{
					fromEndpoints: [{matchLabels: {"k8s:io.kubernetes.pod.namespace": "openbao-csi-provider-system"}}]
					toPorts:       [{ports: [{port: "8200", protocol: "TCP"}]}]
				},
			]
			egress: [
				// TokenReview for Kubernetes auth, service registration
				schema.Net.apiserverOut,
				schema.Net.sameNamespaceOut,
			]
		}

		whitelist: [
			schema.#ClusterRole & {names: ["openbao-namespace-reader"]},
			schema.#ClusterRoleBinding & {
				names: ["openbao-system-openbao-server-binding", "openbao-namespace-reader"]
				// TokenReview for Kubernetes auth
				bind: ["system:auth-delegator"]
			},
		]
	}
}
