package internalca

import "github.com/homelab-selfuryon/platform-components/schema"

// The platform's internal CA: a self-signed root and a ClusterIssuer `internal-ca` for in-cluster
// TLS (OpenBao). Part of `system` rather than `policy`: OpenBao needs a certificate before the
// `policy` set exists.
#InternalCA: {
	#cluster: schema.#Cluster

	component: schema.#Component & {
		name:        "internal-ca"
		description: "Self-signed root CA and the internal-ca ClusterIssuer."
		namespace:   "cert-manager-system"
		set:         "system"
		// cert-manager owns the namespace and its network policies.
		createNamespace: false
		network: policy: false
		dependsOn: ["cert-manager"]

		manifests: global: clusterIssuer: {
			"selfsigned-bootstrap": spec: selfSigned: {}
			"internal-ca": spec: ca: secretName: "internal-ca-key"
		}
		manifests: scoped: "cert-manager-system": certificate: "internal-ca": spec: {
			isCA:       true
			commonName: "homelab-selfuryon internal CA (\(#cluster.name))"
			secretName: "internal-ca-key"
			duration:   "87600h"
			privateKey: {algorithm: "ECDSA", size: 256, rotationPolicy: "Always"}
			issuerRef:  {name: "selfsigned-bootstrap", kind: "ClusterIssuer", group: "cert-manager.io"}
		}

		whitelist: [
			schema.#ClusterIssuer & {names: ["selfsigned-bootstrap", "internal-ca"]},
		]
	}
}
