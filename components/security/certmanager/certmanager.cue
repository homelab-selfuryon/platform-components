package certmanager

import "github.com/homelab-selfuryon/platform-components/schema"

#namespace: "cert-manager-system"

// cert-manager. Issuers are separate components: `internal-ca` (system, needed by OpenBao's TLS)
// and `cluster-issuers` (policy, Let's Encrypt DNS-01 through Cloudflare).
_clusterRoles: [
	"cert-manager-cainjector",
	"cert-manager-cluster-view",
	"cert-manager-controller-approve:cert-manager-io",
	"cert-manager-controller-certificates",
	"cert-manager-controller-certificatesigningrequests",
	"cert-manager-controller-challenges",
	"cert-manager-controller-clusterissuers",
	"cert-manager-controller-ingress-shim",
	"cert-manager-controller-issuers",
	"cert-manager-controller-orders",
	"cert-manager-edit",
	"cert-manager-view",
	"cert-manager-webhook:subjectaccessreviews",
]

#CertManager: {
	#cluster: schema.#Cluster
	#ref:     schema.#Ref
	let _ref = #ref

	component: schema.#Component & {
		name:        "cert-manager"
		description: "cert-manager: certificates from internal and ACME issuers."
		namespace:   #namespace
		set:         "system"

		chart: schema.#Chart & {
			#ref: _ref
			kind: "oci"
			url:  "oci://quay.io/jetstack/charts"
			name: "cert-manager"
		}
		values: {
			crds: enabled: true
			global: leaderElection: namespace: #namespace
			// The check runs as a Helm hook Job; the Kustomization's wait covers the same.
			startupapicheck: enabled: false
			prometheus: enabled:      false
		}

		network: {
			ingress: [
				// Webhook
				schema.Net.apiserverIn & {toPorts: [{ports: [{port: "10250", protocol: "TCP"}]}]},
				schema.Net.sameNamespaceIn,
			]
			egress: [
				schema.Net.apiserverOut,
				schema.Net.sameNamespaceOut,
				// ACME and DNS provider APIs
				schema.Net.world & schema.Net.https,
				// DNS-01 propagation checks query recursive resolvers directly
				schema.Net.world & {toPorts: [{ports: [{port: "53", protocol: "UDP"}, {port: "53", protocol: "TCP"}]}]},
			]
		}

		whitelist: [
			schema.#CRD & {names: ["*.cert-manager.io", "*.acme.cert-manager.io"]},
			schema.#ClusterRole & {names: _clusterRoles},
			schema.#ClusterRoleBinding & {names: [for n in _clusterRoles if n != "cert-manager-cluster-view" && n != "cert-manager-edit" && n != "cert-manager-view" {n}]},
			schema.#ValidatingWebhook & {names: ["cert-manager-webhook"]},
			schema.#MutatingWebhook & {names: ["cert-manager-webhook"]},
		]
	}
}
