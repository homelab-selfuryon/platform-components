package policies

import (
	"list"
)

_policy: "component-whitelist": {
	#ctx: #Context

	global: validatingPolicy: {
		// Names of what a component's ServiceAccount creates at cluster scope; kinds are
		// limited by its ClusterRole, names can not be in RBAC.
		"component-whitelist": spec: {
			validationActions: ["Deny"]
			// Reads request.userInfo, which a background scan does not have: admission only.
			evaluation: background: enabled: false
			matchConditions: [{
				name:       "component-serviceaccount"
				expression: "request.userInfo.username.startsWith('system:serviceaccount:flux-system:component-')"
			}]
			matchConstraints: resourceRules: [
				for g, rs in #ctx.wlResources {
					apiGroups:   [g]
					apiVersions: ["*"]
					operations:  ["CREATE", "UPDATE"]
					resources:   list.SortStrings([for r, _ in rs {r}])
					scope:       "Cluster"
				},
			]
			variables: [
				{name: "allowed", expression: "json.unmarshal(r'\(#ctx.whitelistsJSON)')"},
				{name: "user", expression: "request.userInfo.username"},
				{name: "group", expression: "object.apiVersion.contains('/') ? object.apiVersion.split('/')[0] : ''"},
			]
			validations: [{
				expression:        "variables.user in variables.allowed && variables.allowed[variables.user].exists(r, r.g == variables.group && r.k == object.kind && r.n.exists(p, object.metadata.name.matches(p)))"
				messageExpression: "'The component ServiceAccount may not create ' + object.kind + ' ' + object.metadata.name + ' (not in the component whitelist).'"
				message:           "Not in the component whitelist."
			}]
		}
	}
}
