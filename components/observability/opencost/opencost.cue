package opencost

import "github.com/homelab-selfuryon/platform-components/schema"

// OpenCost: what each namespace, team and environment costs, from the requests and the usage in
// VictoriaMetrics and an on-prem price list (there is no cloud bill). It emits its own
// kube-state-style metrics (pod and namespace labels, requests), which VictoriaMetrics scrapes, so
// there is no kube-state-metrics. API on 9003 (/allocation/compute), UI on 9090; neither is exposed:
// `kubectl -n opencost-system port-forward svc/opencost 9090 9003`.
#OpenCost: {
	#cluster: schema.#Cluster
	#ref:     schema.#Ref
	let _ref = #ref

	// Price list, per hour. PLACEHOLDERS: replace with the real machine.
	//   node cost/h = hardware / months of amortization / 730 h + average watts / 1000 * price per kWh
	//   example: 600 over 36 months = 0.0228/h; 35 W at 0.30/kWh = 0.0105/h; together 0.0333/h
	//   split 70 % CPU over 4 cores, 30 % memory over 7.5 GB
	//   storage: a 1 TB disk at 60 over 36 months, per GB-hour
	let _prices = {
		cpuCoreHour: 0.00583
		ramGBHour:   0.00133
		diskGBHour:  0.0000023
	}

	let _restricted = {
		allowPrivilegeEscalation: false
		runAsNonRoot:             true
		runAsUser:                1001
		runAsGroup:               1001
		capabilities: drop:   ["ALL"]
		seccompProfile: type: "RuntimeDefault"
	}

	component: schema.#Component & {
		name:        "opencost"
		description: "Cost allocation (OpenCost) on VictoriaMetrics with an on-prem price list."
		namespace:   "opencost-system"
		set:         "platform"
		dependsOn:   ["victoria-metrics"]

		chart: schema.#Chart & {
			#ref: _ref
			kind: "oci"
			url:  "oci://ghcr.io/opencost/charts"
			name: "opencost"
		}
		values: {
			clusterName: #cluster.name
			opencost: {
				// The chart starts an MCP server by default; nothing here should answer queries
				// beyond the API.
				mcp: enabled: false
				exporter: {
					defaultClusterId: #cluster.name
					securityContext:  _restricted
					resources: {
						requests: {cpu: "10m", memory: "64Mi"}
						limits: memory: "512Mi"
					}
				}
				prometheus: {
					internal: enabled: false
					external: {
						enabled: true
						url:     "http://victoria-metrics.victoria-metrics-system.svc:8428"
					}
				}
				customPricing: {
					enabled:  true
					provider: "custom"
					costModel: {
						description: "On-prem: hardware amortization plus power (placeholder prices)."
						CPU:         _prices.cpuCoreHour
						spotCPU:     _prices.cpuCoreHour
						RAM:         _prices.ramGBHour
						spotRAM:     _prices.ramGBHour
						GPU:         0
						storage:     _prices.diskGBHour
						// Traffic costs nothing extra on-prem.
						zoneNetworkEgress:     0
						regionNetworkEgress:   0
						internetNetworkEgress: 0
					}
				}
				ui: {
					securityContext: _restricted
					resources: {
						requests: {cpu: "10m", memory: "32Mi"}
						limits: memory: "128Mi"
					}
				}
			}
		}

		// The chart writes `initContainers: null`. The API server drops it, but the Kyverno CLI in CI
		// does not, and `containers + initContainers` then fails on null.
		postRender: [{
			target: {group: "apps", kind: "Deployment", name: "opencost"}
			patch: """
				- op: remove
				  path: /spec/template/spec/initContainers
				"""
		}]

		network: {
			ingress: [{
				// VictoriaMetrics scrapes the exporter's metrics.
				fromEndpoints: [{matchLabels: {"k8s:io.kubernetes.pod.namespace": "victoria-metrics-system"}}]
				toPorts:       [{ports: [{port: "9003", protocol: "TCP"}]}]
			}, {
				// The UI proxies /model to the exporter through the Service.
				fromEndpoints: [{}]
				toPorts:       [{ports: [{port: "9003", protocol: "TCP"}]}]
			}]
			egress: [
				schema.Net.apiserverOut,
				{
					toEndpoints: [{matchLabels: {"k8s:io.kubernetes.pod.namespace": "victoria-metrics-system"}}]
					toPorts:     [{ports: [{port: "8428", protocol: "TCP"}]}]
				},
				{
					toEndpoints: [{}]
					toPorts:     [{ports: [{port: "9003", protocol: "TCP"}]}]
				},
			]
		}

		// Read-only: workloads, nodes, volumes, quotas and configmaps (its own price list); no Secrets.
		whitelist: [
			schema.#ClusterRole & {names: ["opencost"]},
			schema.#ClusterRoleBinding & {names: ["opencost"], bind: []},
		]
	}
}
