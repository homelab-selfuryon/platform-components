package policies

_policy: "tenant-deny-sa-token-secrets": {
	#ctx: #Context

	global: validatingPolicy: {
		"tenant-deny-sa-token-secrets": spec: {
			validationActions: ["Deny"]
			evaluation: background: enabled: true
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
