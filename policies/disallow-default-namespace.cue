package policies

_policy: "disallow-default-namespace": {
	#ctx: #Context

	global: validatingPolicy: {
		"disallow-default-namespace": spec: {
			validationActions: ["Deny"]
			evaluation: background: enabled: true
			// One rule per API group: a rule is the cross product of its groups and resources.
			// CREATE only: the apiserver keeps updating its own objects there.
			matchConstraints: resourceRules: [
				for g, r in {
					"":    ["pods"]
					apps:  ["deployments", "statefulsets", "daemonsets"]
					batch: ["jobs", "cronjobs"]
				} {
					apiGroups:   [g]
					apiVersions: ["v1"]
					operations:  ["CREATE"]
					resources:   r
				},
			]
			validations: [{
				expression: "object.metadata.?namespace.orValue('') != 'default'"
				message:    "Workloads must not run in the default namespace."
			}]
		}
	}
}
