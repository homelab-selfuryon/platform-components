package fluxoperator

import (
	"strings"
	"github.com/homelab-selfuryon/platform-components/schema"
)

#namespace: "flux-system"

// Flux Operator and the FluxInstance that installs Flux itself. The same render is applied by
// hand once (`cue cmd bootstrap`); afterwards Flux manages both, including upgrades of the
// operator. What Flux applies next (the `gitops` artifact) is set up by bootstrap, not here.
//
// Multi-tenant lockdown: the default ServiceAccount of every Kustomization has no rights, no
// cross-namespace references, no remote bases. Every Kustomization names its own ServiceAccount.
#Flux: {
	#cluster:  schema.#Cluster
	#operator: schema.#Ref
	#flux:     schema.#Ref

	component: schema.#Component & {
		name:        "flux-operator"
		description: "Flux Operator and the FluxInstance (multi-tenant lockdown)."
		namespace:   #namespace
		set:         "system"
		// Created by bootstrap together with the first Flux objects.
		createNamespace: false
		privileged:      true
		reason:          "Flux itself: runs the controllers every other component is delivered by."
		// The FluxInstance generates Flux's own NetworkPolicies in flux-system.
		network: policy: false

		chart: schema.#Chart & {
			#ref: #operator
			kind: "oci"
			url:  "oci://ghcr.io/controlplaneio-fluxcd/charts"
			name: "flux-operator"
		}
		values: {
			// No web UI: Flux is driven through the gitops artifact and the CLI.
			web: enabled: false
		}

		manifests: scoped: (#namespace): fluxInstance: flux: spec: {
			distribution: {
				version:  strings.TrimPrefix(#flux.version, "v")
				registry: "ghcr.io/fluxcd"
				artifact: "oci://ghcr.io/controlplaneio-fluxcd/flux-operator-manifests"
			}
			// No notification-controller: nothing sends or receives alerts yet. helm-controller
			// serves the (listed) HelmRelease exceptions.
			components: [
				"source-controller",
				"kustomize-controller",
				"helm-controller",
			]
			cluster: {
				type:                        "kubernetes"
				size:                        "small"
				multitenant:                 true
				tenantDefaultServiceAccount: "default"
				networkPolicy:               true
				domain:                      "cluster.local"
			}
		}

		whitelist: [
			schema.#CRD & {names: ["*.fluxcd.controlplane.io", "*.fluxcd.io"]},
			schema.#ClusterRole & {names: ["flux-operator", "flux-operator-edit", "flux-operator-view"]},
			schema.#ClusterRoleBinding & {names: ["flux-operator"], bind: ["cluster-admin"]},
		]
	}
}
