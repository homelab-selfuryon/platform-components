package policies

_policy: "tenant-deny-sa-token-secrets": {
	#ctx: #Context

	global: validatingPolicy: {
		"tenant-deny-sa-token-secrets": spec: {
			validationActions: ["Deny"]
			// Admission only: a background scan would need the reports controller to read every
			// Secret in the cluster.
			evaluation: background: enabled: false
			matchConstraints: {
				namespaceSelector: _tenantNS
				resourceRules: [{
					apiGroups:   [""]
					apiVersions: ["v1"]
					operations:  ["CREATE", "UPDATE"]
					resources:   ["secrets"]
				}]
			}
			validations: [{
				expression: "object.?type.orValue('Opaque') != 'kubernetes.io/service-account-token'"
				message:    "Long-lived ServiceAccount token Secrets are not allowed: use projected, audience-bound tokens."
			}]
		}
	}
}
