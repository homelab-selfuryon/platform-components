package policies

_policy: "tenant-deny-shell-access": {
	#ctx: #Context

	global: validatingPolicy: {
		"tenant-deny-shell-access": spec: {
			validationActions: ["Deny"]
			// Reads request.userInfo, which a background scan does not have: admission only.
			evaluation: background: enabled: false
			// Break-glass (system:masters) is audited, not blocked.
			matchConditions: [{name: "not-break-glass", expression: "!('system:masters' in request.userInfo.groups)"}]
			matchConstraints: {
				namespaceSelector: _tenantNS
				resourceRules: [{
					apiGroups:   [""]
					apiVersions: ["v1"]
					operations:  ["CONNECT"]
					resources:   ["pods/exec", "pods/attach", "pods/portforward"]
				}, {
					apiGroups:   [""]
					apiVersions: ["v1"]
					operations:  ["CREATE", "UPDATE"]
					resources:   ["pods/ephemeralcontainers"]
				}]
			}
			validations: [{
				expression: "false"
				message:    "No exec, attach, port-forward or ephemeral containers in tenant namespaces."
			}]
		}
	}
}
