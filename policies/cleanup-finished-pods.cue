package policies

_policy: "cleanup-finished-pods": {
	#ctx: #Context

	// Finished pods that no Job owns (Jobs clean up after themselves).
	global: deletingPolicy: "cleanup-finished-pods": spec: {
		schedule: "0 * * * *"
		matchConstraints: resourceRules: [{
			apiGroups:   [""]
			apiVersions: ["v1"]
			operations:  ["*"]
			resources:   ["pods"]
			scope:       "Namespaced"
		}]
		conditions: [{
			name:       "finished"
			expression: "object.?status.?phase.orValue('') in ['Succeeded', 'Failed']"
		}, {
			name:       "not-from-a-job"
			expression: "!object.metadata.?ownerReferences.orValue([]).exists(o, o.kind == 'Job')"
		}]
	}
	clusterRole: "kyverno:cleanup-pods": {
		metadata: labels: "rbac.kyverno.io/aggregate-to-cleanup-controller": "true"
		rules: [{
			apiGroups: [""]
			resources: ["pods"]
			verbs:     ["get", "list", "watch", "delete"]
		}]
	}
}
