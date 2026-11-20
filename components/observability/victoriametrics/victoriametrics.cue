package victoriametrics

import "github.com/homelab-selfuryon/platform-components/schema"

// VictoriaMetrics single-node: the cluster's metrics store, scraping its targets itself (no
// vmagent, no operator, no node-exporter). It scrapes the kubelets (node and cAdvisor metrics),
// OpenCost and itself; OpenCost reads it through the Prometheus API. No UI and no Gateway route:
// `kubectl port-forward` to 8428 (vmui at /vmui) until human access to web UIs is decided.
#VictoriaMetrics: {
	#cluster: schema.#Cluster
	#ref:     schema.#Ref
	let _ref = #ref

	// Kubelet endpoints. TODO: Talos' kubelet serving certificates are self-signed until
	// `rotate-server-certificates` and a CSR approver are in place (as for metrics-server); then
	// verify them against the cluster CA.
	let _kubelet = {
		scheme:                "https"
		kubernetes_sd_configs: [{role: "node"}]
		tls_config: insecure_skip_verify: true
		bearer_token_file: "/var/run/secrets/kubernetes.io/serviceaccount/token"
		relabel_configs:   [{source_labels: ["__meta_kubernetes_node_name"], target_label: "node"}]
	}

	component: schema.#Component & {
		name:        "victoria-metrics"
		description: "Metrics store (VictoriaMetrics single-node), scrapes the kubelets."
		namespace:   "victoria-metrics-system"
		set:         "platform"

		chart: schema.#Chart & {
			#ref: _ref
			kind: "oci"
			url:  "oci://ghcr.io/victoriametrics/helm-charts"
			name: "victoria-metrics-single"
		}
		values: {
			global: image: registry: "docker.io"
			server: {
				// Service `victoria-metrics:8428` (Prometheus API under /prometheus).
				fullnameOverride: "victoria-metrics"
				retentionPeriod:  "90d"
				extraArgs: {
					"envflag.enable": true
					"envflag.prefix": "VM_"
					loggerFormat:     "json"
					// The cluster is IPv6-first.
					enableTCP6: true
					// The scrape config is a ConfigMap and the chart does not restart the pod when it
					// changes: re-read it every minute.
					"promscrape.configCheckInterval": "1m"
				}
				persistentVolume: {
					enabled: true
					size:    "10Gi"
				}
				// The chart renders empty security contexts; Pod Security restricted needs them set.
				// local-path volumes are created world-writable, so a non-root UID can write them.
				podSecurityContext: {
					enabled:      true
					runAsNonRoot: true
					runAsUser:    65534
					runAsGroup:   65534
					fsGroup:      65534
					seccompProfile: type: "RuntimeDefault"
				}
				securityContext: {
					enabled:                  true
					allowPrivilegeEscalation: false
					readOnlyRootFilesystem:   true
					capabilities: drop: ["ALL"]
				}
				// One small node: the store is capped; VictoriaMetrics sizes its caches from the limit.
				resources: {
					requests: {cpu: "50m", memory: "256Mi"}
					limits: memory: "512Mi"
				}
				scrape: {
					enabled: true
					config: {
						global: scrape_interval: "30s"
						scrape_configs: [
							{job_name: "victoriametrics", static_configs: [{targets: ["localhost:8428"]}]},
							_kubelet & {job_name: "kubelet", metrics_path: "/metrics"},
							_kubelet & {job_name: "cadvisor", metrics_path: "/metrics/cadvisor"},
							// OpenCost: its cost metrics and the kube-state-style metrics it emits (their
							// namespace and pod labels are the objects', not the target's).
							{job_name: "opencost", honor_labels: true, static_configs: [{targets: ["opencost.opencost-system.svc:9003"]}]},
						]
					}
				}
			}
		}

		network: {
			ingress: [{
				// OpenCost queries the Prometheus API.
				fromEndpoints: [{matchLabels: {"k8s:io.kubernetes.pod.namespace": "opencost-system"}}]
				toPorts:       [{ports: [{port: "8428", protocol: "TCP"}]}]
			}]
			egress: [
				schema.Net.apiserverOut,
				// kubelets
				{toEntities: ["host", "remote-node"], toPorts: [{ports: [{port: "10250", protocol: "TCP"}]}]},
				{
					toEndpoints: [{matchLabels: {"k8s:io.kubernetes.pod.namespace": "opencost-system"}}]
					toPorts:     [{ports: [{port: "9003", protocol: "TCP"}]}]
				},
			]
		}

		// Read-only discovery (nodes, nodes/metrics, pods, services, endpoints, ingresses; no Secrets).
		whitelist: [
			schema.#ClusterRole & {names: ["victoria-metrics"]},
			schema.#ClusterRoleBinding & {names: ["victoria-metrics"], bind: []},
		]
	}
}
