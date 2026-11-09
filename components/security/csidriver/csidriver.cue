package csidriver

import "github.com/homelab-selfuryon/platform-components/schema"

// Secrets Store CSI driver: mounts secrets from OpenBao (through the provider in
// `openbao-csi-provider`) as files. `syncSecret` is on for the platform components that insist on
// a Kubernetes Secret; admission allows `secretObjects` in `*-system` namespaces only.
#CSIDriver: {
	#cluster: schema.#Cluster
	#ref:     schema.#Ref

	component: schema.#Component & {
		name:        "secrets-store-csi-driver"
		description: "Secrets Store CSI driver (files from OpenBao)."
		namespace:   "secrets-store-csi-driver-system"
		set:         "platform"
		psa: {
			level:  "privileged"
			reason: "The node plugin is a privileged DaemonSet with host paths: it mounts volumes into other pods' mount namespaces."
		}

		chart: schema.#Chart & {
			kind:        "helm"
			url:         "https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts"
			name:        "secrets-store-csi-driver"
			version:     #ref.version
			includeCRDs: true
		}
		values: {
			// The CRDs come from the chart's crds/ directory; its upgrade hook Jobs (kubectl) are off.
			linux: crds: enabled: false
			syncSecret: enabled: true
			enableSecretRotation: true
			rotationPollInterval: "2m"
			// Kubelet root on Talos is the default; the providers directory is shared with the OpenBao provider.
			linux: providersDir: "/var/run/secrets-store-csi-providers"
		}

		network: {
			ingress: [schema.Net.sameNamespaceIn]
			egress:  [schema.Net.apiserverOut]
		}

		whitelist: [
			schema.#CRD & {names: ["*.secrets-store.csi.x-k8s.io"]},
			schema.#CSIDriver & {names: ["secrets-store.csi.k8s.io"]},
			schema.#ClusterRole & {names: ["secretproviderclasses-admin-role", "secretproviderclasses-role", "secretproviderclasses-viewer-role", "secretproviderclasspodstatuses-viewer-role", "secretprovidersyncing-role"]},
			schema.#ClusterRoleBinding & {names: ["secretproviderclasses-rolebinding", "secretprovidersyncing-rolebinding"]},
		]
	}
}
