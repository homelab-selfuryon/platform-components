package metricsserver

import "github.com/homelab-selfuryon/platform-components/schema"

// metrics-server for `kubectl top` and autoscaling.
#MetricsServer: {
	#cluster: schema.#Cluster
	#ref:     schema.#Ref

	component: schema.#Component & {
		name:        "metrics-server"
		description: "Resource metrics API."
		namespace:   "metrics-server-system"
		set:         "platform"
		// The chart binds a Role in kube-system (extension-apiserver-authentication-reader).
		targetNamespace: false
		rbac: namespaced: "kube-system": [{
			apiGroups: ["rbac.authorization.k8s.io"]
			resources: ["rolebindings"]
			verbs:     ["get", "list", "watch", "create", "update", "patch", "delete"]
		}, {
			apiGroups:     ["rbac.authorization.k8s.io"]
			resources:     ["roles"]
			verbs:         ["bind"]
			resourceNames: ["extension-apiserver-authentication-reader"]
		}]

		chart: schema.#Chart & {
			kind:    "helm"
			url:     "https://kubernetes-sigs.github.io/metrics-server/"
			name:    "metrics-server"
			version: #ref.version
		}
		values: {
			// TODO: Talos' kubelet serving certificates are self-signed until
			// `rotate-server-certificates` and a CSR approver are in place; then drop this flag.
			args: ["--kubelet-insecure-tls"]
		}

		network: {
			ingress: [
				// kube-apiserver aggregation layer
				schema.Net.apiserverIn & {toPorts: [{ports: [{port: "10250", protocol: "TCP"}]}]},
			]
			egress: [
				schema.Net.apiserverOut,
				// kubelets
				{toEntities: ["host", "remote-node"], toPorts: [{ports: [{port: "10250", protocol: "TCP"}]}]},
			]
		}

		whitelist: [
			schema.#APIService & {names: ["v1beta1.metrics.k8s.io"]},
			schema.#ClusterRole & {names: ["system:metrics-server", "system:metrics-server-aggregated-reader"]},
			schema.#ClusterRoleBinding & {
				names: ["metrics-server:system:auth-delegator", "system:metrics-server"]
				bind:  ["system:auth-delegator"]
			},
		]
	}
}
