package kyverno

import "github.com/homelab-selfuryon/platform-components/schema"

// Kyverno policy engine. Controllers run with chart defaults (one replica each), which fits a
// single-node cluster. The policies are a separate component in the `policy` set.
#Kyverno: {
	#cluster: schema.#Cluster
	#ref:     schema.#Ref
	let _ref = #ref

	component: schema.#Component & {
		name:          "kyverno"
		description:   "Kyverno: admission control and background scans with CEL policies."
		namespace:     "kyverno-system"
		set:           "system"
		privileged:    true
		reason:        "Admission controller: owns webhooks that gate every request and the policy CRDs; a restricted ServiceAccount could not manage them."
		variant:       "helmrelease"
		variantReason: "The chart's hooks matter: post-upgrade migrates stored resources to new CRD versions, pre-delete removes the webhooks and scales the controllers to zero so a removal cannot lock the API server. Rendered without Helm they would be dropped."

		chart: schema.#Chart & {
			#ref: _ref
			kind: "oci"
			url:  "oci://ghcr.io/kyverno/charts"
			name: "kyverno"
		}
		// The post-upgrade job that migrates stored policies to new CRD versions has no delete policy in
		// the chart and would stay until the next upgrade: removed a day after it finishes (its log
		// stays readable until then).
		postRender: [{
			target: {group: "batch", kind: "Job", name: "kyverno-migrate-resources"}
			patch: """
				apiVersion: batch/v1
				kind: Job
				metadata:
				  name: kyverno-migrate-resources
				spec:
				  ttlSecondsAfterFinished: 86400
				"""
		}]

		values: {
			crds: install: true
			// Checking images calls registries and the Sigstore infrastructure; nothing else.
			features: policyExceptions: enabled: false
		}

		network: {
			ingress: [
				// Admission and cleanup webhooks
				schema.Net.apiserverIn & {toPorts: [{ports: [{port: "9443", protocol: "TCP"}]}]},
			]
			egress: [
				schema.Net.apiserverOut,
				// Registries and Sigstore for image verification
				schema.Net.world & schema.Net.https,
				schema.Net.sameNamespaceOut,
			]
		}

		whitelist: [
			schema.#CRD & {names: ["*.kyverno.io", "*.policies.kyverno.io", "*.wgpolicyk8s.io", "*.reports.kyverno.io"]},
			schema.#ClusterRole & {names: ["*"]},
			schema.#ClusterRoleBinding & {names: ["*"]},
			schema.#ValidatingWebhook & {names: ["kyverno-*"]},
			schema.#MutatingWebhook & {names: ["kyverno-*"]},
		]
	}
}
