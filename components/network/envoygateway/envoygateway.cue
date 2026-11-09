package envoygateway

import "github.com/homelab-selfuryon/platform-components/schema"

#namespace: "envoy-gateway-system"

// Envoy Gateway: the Gateway API implementation. The Gateways, their certificates and the
// EnvoyProxy are in the `gateways` component (policy set).
#EnvoyGateway: {
	#cluster: schema.#Cluster
	#ref:     schema.#Ref
	let _ref = #ref

	component: schema.#Component & {
		name:        "envoy-gateway"
		description: "Envoy Gateway controller (Gateway API)."
		namespace:   #namespace
		set:         "platform"
		dependsOn:   ["gateway-api"]

		chart: schema.#Chart & {
			#ref:        _ref
			kind:        "oci"
			url:         "oci://docker.io/envoyproxy"
			name:        "gateway-helm"
			releaseName: "eg"
		}
		values: {
			config: envoyGateway: {
				gateway: controllerName: "gateway.envoyproxy.io/gatewayclass-controller"
				provider: type:          "Kubernetes"
				logging: level: default: "info"
			}
			// No pod topology webhook.
			topologyInjector: enabled: false
		}

		// The safe-upgrades policy for the Gateway API CRDs ships with them (gateway-api).
		postRender: [for k in ["ValidatingAdmissionPolicy", "ValidatingAdmissionPolicyBinding"] {
			target: {kind: k, name: "safe-upgrades.gateway.networking.k8s.io"}
			patch: """
				$patch: delete
				apiVersion: admissionregistration.k8s.io/v1
				kind: \(k)
				metadata:
				  name: safe-upgrades.gateway.networking.k8s.io
				"""
		}]

		network: {
			ingress: [
				schema.Net.sameNamespaceIn,
				// Admission webhooks of the controller
				schema.Net.apiserverIn & {toPorts: [{ports: [{port: "9443", protocol: "TCP"}]}]},
				// Traffic the proxies terminate: the Gateways' listeners (10080/10443 behind 80/443)
				{
					fromEntities: ["world", "cluster", "host", "remote-node"]
					toPorts:      [{ports: [{port: "10080", protocol: "TCP"}, {port: "10443", protocol: "TCP"}]}]
				},
			]
			egress: [
				schema.Net.apiserverOut,
				schema.Net.sameNamespaceOut,
				// Backends in the tenant namespaces (their own policies decide)
				{toEntities: ["cluster"]},
			]
		}

		whitelist: [
			schema.#ClusterRole & {names: ["eg-gateway-helm-envoy-gateway-role"]},
			schema.#ClusterRoleBinding & {names: ["eg-gateway-helm-envoy-gateway-rolebinding"]},
		]
	}
}
