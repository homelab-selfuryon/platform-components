package policies

import (
	"list"
	"strings"

	"github.com/homelab-selfuryon/platform-components/schema"
)

_policy: "cleanup-preview-namespaces": {
	#ctx: #Context

	// Argo CD creates the preview namespaces (`CreateNamespace=true`) but never deletes them: when
	// the PR closes, the ApplicationSet removes the Application and Argo prunes its objects, and
	// the namespace stays with what the platform generated in it (default-deny, LimitRange, quota).
	// Deleted here once no Application points at it any more. An hour of age covers the window
	// between the Application and its first sync. If the Applications cannot be listed, the
	// condition errors and nothing is deleted.
	let _names = "^(" + strings.Join(list.SortStrings([for n, _ in #ctx.teams {n}]), "|") + ")-pr-[0-9]+$"

	global: deletingPolicy: "cleanup-preview-namespaces": spec: {
		schedule: "30 * * * *"
		matchConstraints: {
			resourceRules: [{
				apiGroups:   [""]
				apiVersions: ["v1"]
				operations:  ["*"]
				resources:   ["namespaces"]
				scope:       "Cluster"
			}]
			objectSelector: matchLabels: (_env): "preview"
		}
		conditions: [{
			name:       "preview-name"
			expression: "object.metadata.name.matches('\(_names)')"
		}, {
			name:       "older-than-an-hour"
			expression: "time.now() - timestamp(object.metadata.creationTimestamp) > duration('1h')"
		}, {
			name:       "no-application"
			expression: "!dyn(resource.List('argoproj.io/v1alpha1', 'applications', '\(schema.#ArgoCDNamespace)').items).exists(a, a.spec.?destination.?namespace.orValue('') == object.metadata.name)"
		}]
	}
	clusterRole: "kyverno:cleanup-preview-namespaces": {
		metadata: labels: "rbac.kyverno.io/aggregate-to-cleanup-controller": "true"
		rules: [{
			apiGroups: [""]
			resources: ["namespaces"]
			verbs:     ["get", "list", "watch", "delete"]
		}, {
			apiGroups: ["argoproj.io"]
			resources: ["applications"]
			verbs:     ["get", "list", "watch"]
		}]
	}
}
