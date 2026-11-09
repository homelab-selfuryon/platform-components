package gateways

import (
	"github.com/homelab-selfuryon/platform-components/schema"
)

#namespace: "envoy-gateway-system"

// The shared edge: one GatewayClass, an EnvoyProxy with merged Gateways (one Envoy deployment for
// all of them) and one Gateway per environment, each with an `https` listener and a wildcard
// certificate for the environment's hostnames (`*.<domain>`, `*.staging.<domain>`,
// `*.preview.<domain>`). Routes attach from the namespaces of that environment only.
//
// Apps write only an HTTPRoute (platform-kit); the Gateway of an environment is named after it.
#Gateways: {
	#cluster: schema.#Cluster

	let _domain = #cluster.domain

	// environment -> wildcard hostname
	let _envs = {
		prod:    "*.\(_domain)"
		staging: "*.staging.\(_domain)"
		preview: "*.preview.\(_domain)"
	}

	component: schema.#Component & {
		name:        "gateways"
		description: "GatewayClass, EnvoyProxy, the preview/staging/prod Gateways and their certificates."
		namespace:   #namespace
		set:         "policy"
		// envoy-gateway owns the namespace and its network policies.
		createNamespace: false
		network: policy: false
		dependsOn: ["envoy-gateway", "cluster-issuers"]

		manifests: global: gatewayClass: envoy: spec: {
			controllerName: "gateway.envoyproxy.io/gatewayclass-controller"
			parametersRef: {
				group:     "gateway.envoyproxy.io"
				kind:      "EnvoyProxy"
				name:      "envoy"
				namespace: #namespace
			}
		}

		manifests: scoped: (#namespace): {
			envoyProxy: envoy: spec: {
				mergeGateways: true
				provider: {
					type: "Kubernetes"
					kubernetes: {
						envoyDeployment: {
							replicas: 1
							pod: {
								// The merged proxy carries no per-Gateway label: the label below is what
								// app network policies select (see docs/gateways.md).
								labels: "\(schema.#Prefix)/component": "gateway-proxy"
								securityContext: {
									runAsNonRoot: true
									runAsUser:    65532
									runAsGroup:   65532
									seccompProfile: type: "RuntimeDefault"
								}
							}
							container: securityContext: {
								allowPrivilegeEscalation: false
								capabilities: drop: ["ALL"]
								runAsNonRoot: true
								runAsUser:    65532
							}
						}
						envoyService: {
							type:                  "LoadBalancer"
							externalTrafficPolicy: "Cluster"
						}
					}
				}
			}

			for env, host in _envs {
				gateway: (env): spec: {
					gatewayClassName: "envoy"
					listeners: [{
						name:     "https"
						protocol: "HTTPS"
						port:     443
						hostname: host
						tls: {
							mode:            "Terminate"
							certificateRefs: [{kind: "Secret", name: "wildcard-\(env)"}]
						}
						allowedRoutes: {
							namespaces: {
								from: "Selector"
								selector: matchLabels: "\(schema.#Prefix)/env": env
							}
							kinds: [{kind: "HTTPRoute"}]
						}
					}]
				}
				certificate: "wildcard-\(env)": spec: {
					secretName: "wildcard-\(env)"
					dnsNames:   [host]
					duration:   "2160h"
					privateKey: {algorithm: "ECDSA", size: 256, rotationPolicy: "Always"}
					issuerRef:  {name: "letsencrypt", kind: "ClusterIssuer", group: "cert-manager.io"}
				}
			}
		}

		whitelist: [
			schema.#GatewayClass & {names: ["envoy"]},
		]
	}
}
