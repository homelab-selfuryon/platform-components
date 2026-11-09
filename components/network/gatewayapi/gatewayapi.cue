package gatewayapi

import "github.com/homelab-selfuryon/platform-components/schema"

// The Gateway API CRDs (standard channel) and the Envoy Gateway CRDs, from the Envoy Gateway CRDs
// chart. Separate from the controller (`envoy-gateway`, which ships none) so CRDs and controller
// upgrade on their own; keep both on the same Envoy Gateway minor version.
#GatewayAPI: {
	#cluster: schema.#Cluster
	#ref:     schema.#Ref
	let _ref = #ref

	component: schema.#Component & {
		name:        "gateway-api"
		description: "Gateway API (standard channel) and Envoy Gateway CRDs."
		set:         "system"

		chart: schema.#Chart & {
			#ref: _ref
			kind: "oci"
			url:  "oci://docker.io/envoyproxy"
			name: "gateway-crds-helm"
		}
		values: crds: {
			gatewayAPI: {enabled: true, channel: "standard"}
			envoyGateway: enabled: true
		}

		whitelist: [
			schema.#CRD & {names: ["*.gateway.networking.k8s.io", "*.gateway.networking.x-k8s.io", "*.gateway.envoyproxy.io"]},
			schema.#ValidatingAdmissionPolicy & {names: ["safe-upgrades.gateway.networking.k8s.io"]},
			schema.#ValidatingAdmissionPolicyBinding & {names: ["safe-upgrades.gateway.networking.k8s.io"]},
		]
	}
}
