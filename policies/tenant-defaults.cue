package policies

import (
	"github.com/homelab-selfuryon/platform-components/schema"
	core_v1 "cue.dev/x/k8s.io/api/core/v1"
)

_policy: "tenant-defaults": {
	#ctx: #Context

	// Defaults for every tenant namespace, existing and future: nothing in, egress only DNS; and
	// requests/limits for containers that declare none. Applications open what they need with
	// their own CiliumNetworkPolicy (platform-kit renders it). Platform namespaces get theirs
	// from the component render.
	global: generatingPolicy: {
		"tenant-default-deny": spec: (#Generate & {
			#condition: "has(object.metadata.labels) && '\(_team)' in object.metadata.labels"
			#object: {
				apiVersion: "cilium.io/v2"
				kind:       "CiliumNetworkPolicy"
				metadata: name: "default-deny"
				spec: (_cnpSpec & {
					#spec: {
						description:      "Default deny (tenant-default-deny): no ingress, egress only DNS. Allow traffic with policies next to the workload."
						endpointSelector: {}
						ingress:          [{}]
						egress:           [schema.Net.dns]
					}
				}).out
			}
		}).spec

		"tenant-default-limits": spec: (#Generate & {
			#condition: "has(object.metadata.labels) && '\(_team)' in object.metadata.labels"
			#object: {
				apiVersion: "v1"
				kind:       "LimitRange"
				metadata: name: "default-limits"
				spec: core_v1.#LimitRangeSpec & {
					limits: [{
						type:           "Container"
						defaultRequest: {cpu: "10m", memory: "32Mi"}
						default: memory: "256Mi"
					}]
				}
			}
		}).spec

		for _, t in #ctx.teams {
			"preview-quota-\(t.name)": spec: (#Generate & {
				#condition: "has(object.metadata.labels) && object.metadata.labels[?'\(_team)'].orValue('') == '\(t.name)' && object.metadata.labels[?'\(_env)'].orValue('') == 'preview'"
				#object: {
					apiVersion: "v1"
					kind:       "ResourceQuota"
					metadata: name: "team-quota"
					spec: core_v1.#ResourceQuotaSpec & {
						hard: {
							"requests.cpu":         t.quota.preview.requestsCPU
							"requests.memory":      t.quota.preview.requestsMemory
							"limits.memory":        t.quota.preview.limitsMemory
							pods:                   t.quota.preview.pods
							persistentvolumeclaims: t.quota.preview.persistentVolumeClaims
							"requests.storage":     t.quota.preview.requestsStorage
						}
					}
				}
			}).spec
		}
	}
	// The Kyverno controllers create what the generating policies describe.
	global: clusterRole: "kyverno:generate-tenant-defaults": {
		metadata: labels: {
			"rbac.kyverno.io/aggregate-to-background-controller": "true"
			"rbac.kyverno.io/aggregate-to-admission-controller":  "true"
		}
		rules: [{
			apiGroups: ["cilium.io"]
			resources: ["ciliumnetworkpolicies"]
			verbs:     ["create", "update", "patch", "delete", "get", "list", "watch"]
		}, {
			apiGroups: [""]
			resources: ["limitranges", "resourcequotas"]
			verbs:     ["create", "update", "patch", "delete", "get", "list", "watch"]
		}]
	}
}
