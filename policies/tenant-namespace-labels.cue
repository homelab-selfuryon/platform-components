package policies

_policy: "tenant-namespace-labels": {
	#ctx: #Context

	global: validatingPolicy: {
		// Namespaces carrying a team label are tenant namespaces: Pod Security restricted, and the
		// name must say which team and environment they are (admission selects on these labels).
		"tenant-namespace-labels": spec: {
			validationActions: ["Deny"]
			evaluation: background: enabled: true
			matchConstraints: resourceRules: [{
				apiGroups:   [""]
				apiVersions: ["v1"]
				operations:  ["CREATE", "UPDATE"]
				resources:   ["namespaces"]
			}]
			variables: [
				{name: "labels", expression: "object.metadata.?labels.orValue({})"},
				{name: "team", expression: "variables.labels[?'\(_team)'].orValue('')"},
				{name: "env", expression: "variables.labels[?'\(_env)'].orValue('')"},
			]
			validations: [
				{
					expression: "variables.team == '' || variables.labels[?'pod-security.kubernetes.io/enforce'].orValue('') == 'restricted'"
					message:    "Tenant namespaces must enforce Pod Security `restricted`."
				},
				{
					expression: "variables.team == '' || (variables.env in ['staging', 'prod'] && object.metadata.name == variables.team + '-' + variables.env) || (variables.env == 'preview' && object.metadata.name.matches('^' + variables.team + '-pr-[0-9]+$'))"
					message:    "Namespace name must be <team>-<env> (staging, prod) or <team>-pr-<n> (env preview) for its team and env labels."
				},
				{
					expression: "!object.metadata.name.matches('^[a-z0-9]+-pr-[0-9]+$') || (variables.team != '' && variables.env == 'preview')"
					message:    "Preview namespaces (<team>-pr-<n>) need the team label and env=preview."
				},
			]
		}
	}
}
