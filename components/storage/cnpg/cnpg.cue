package cnpg

import "github.com/homelab-selfuryon/platform-components/schema"

// CloudNativePG operator. The databases themselves (one `Cluster` per app and environment)
// come with the apps (`database: postgres` in deploy.cue).
#CNPG: {
	#cluster: schema.#Cluster
	#ref:     schema.#Ref

	component: schema.#Component & {
		name:        "cnpg"
		description: "CloudNativePG operator."
		namespace:   "cnpg-system"
		set:         "platform"

		chart: schema.#Chart & {
			kind:        "helm"
			url:         "https://cloudnative-pg.github.io/charts"
			name:        "cloudnative-pg"
			version:     #ref.version
			releaseName: "cnpg"
		}
		values: {
			crds: create:                  true
			config: clusterWide:           true
			monitoring: podMonitorEnabled: false
		}

		network: {
			ingress: [
				// Admission webhooks
				schema.Net.apiserverIn & {toPorts: [{ports: [{port: "9443", protocol: "TCP"}]}]},
			]
			egress: [
				schema.Net.apiserverOut,
				// Instance managers: status endpoint (8000) and PostgreSQL (5432) of every cluster.
				{toEntities: ["cluster"], toPorts: [{ports: [{port: "8000", protocol: "TCP"}, {port: "5432", protocol: "TCP"}]}]},
			]
		}

		whitelist: [
			schema.#CRD & {names: ["*.postgresql.cnpg.io"]},
			schema.#ClusterRole & {names: ["cnpg-cloudnative-pg", "cnpg-cloudnative-pg-edit", "cnpg-cloudnative-pg-view"]},
			schema.#ClusterRoleBinding & {names: ["cnpg-cloudnative-pg"]},
			schema.#MutatingWebhook & {names: ["cnpg-mutating-webhook-configuration"]},
			schema.#ValidatingWebhook & {names: ["cnpg-validating-webhook-configuration"]},
		]
	}
}
