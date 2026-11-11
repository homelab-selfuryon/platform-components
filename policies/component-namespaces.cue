package policies

import (
	"encoding/json"
)

_policy: "component-namespaces": {
	#ctx: #Context

	global: validatingPolicy: {
		"component-namespaces": spec: {
			validationActions: ["Deny"]
			// Reads request.userInfo, which a background scan does not have: admission only.
			evaluation: background: enabled: false
			matchConditions: [{
				name:       "component-with-namespaces"
				expression: "request.userInfo.username in \(json.Marshal([for u, _ in #ctx.nsRules {u}]))"
			}]
			matchConstraints: resourceRules: [{
				apiGroups:   #ctx.nsGroups
				apiVersions: ["*"]
				operations:  ["CREATE", "UPDATE", "DELETE"]
				resources:   ["*"]
				scope:       "Namespaced"
			}]
			variables: [
				{name: "allowed", expression: json.Marshal(#ctx.nsRules)},
				{name: "target", expression: "request.operation == 'DELETE' ? oldObject : object"},
			]
			validations: [{
				expression: "variables.allowed[request.userInfo.username].exists(p, variables.target.metadata.namespace.matches(p))"
				message:    "The component ServiceAccount may not write to this namespace."
			}]
		}
	}
}
