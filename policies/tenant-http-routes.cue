package policies

// HTTPRoutes of the teams: their own host names on their environment's Gateway. The listeners take
// routes from every namespace of the environment, and the wildcard certificate covers any name: a
// team could otherwise claim another team's host (or a more specific path on it) and take its
// traffic. Host names are the ones platform-kit renders:
//
//   prod     <app>.<domain>             staging  <app>.staging.<domain>
//   preview  <app>-pr-<n>.preview.<domain>, <n> from the namespace <team>-pr-<n>
//
// where <app> is the team name or starts with `<team>-` (apps are named `<team>-*`).
_policy: "tenant-http-routes": {
	#ctx: #Context

	global: validatingPolicy: {
		"tenant-http-routes": spec: {
			validationActions: ["Deny"]
			evaluation: background: enabled: true
			matchConstraints: {
				namespaceSelector: _tenantNS
				resourceRules: [{
					apiGroups:   ["gateway.networking.k8s.io"]
					apiVersions: ["*"]
					operations:  ["CREATE", "UPDATE"]
					resources:   ["httproutes"]
				}]
			}
			variables: [
				{name: "labels", expression: "namespaceObject.?metadata.?labels.orValue({})"},
				{name: "team", expression: "variables.labels[?'\(_team)'].orValue('')"},
				{name: "env", expression: "variables.labels[?'\(_env)'].orValue('')"},
				// `-pr-<n>` for previews (the namespace without the team), else nothing.
				{name: "suffix", expression: "variables.env == 'preview' ? object.metadata.namespace.substring(size(variables.team)) : ''"},
				{name: "zone", expression: "variables.env == 'prod' ? '\(#ctx.domain)' : variables.env + '.\(#ctx.domain)'"},
			]
			validations: [{
				expression: """
					variables.team.matches('^[a-z0-9]+$') && variables.env in ['preview', 'staging', 'prod']
					&& size(object.spec.?hostnames.orValue([])) > 0
					&& object.spec.hostnames.all(h, h.endsWith('.' + variables.zone)
					  && h.substring(0, size(h) - size(variables.zone) - 1).matches('^' + variables.team + '(-[a-z0-9-]+)?' + variables.suffix + '$'))
					"""
				messageExpression: "'Host names must be <team>[-<name>]' + variables.suffix + '.' + variables.zone + ' (one label, your team as prefix).'"
				message:           "Host names must be the team's own, in the environment's zone."
			}, {
				expression: """
					object.spec.?parentRefs.orValue([]).all(p,
					  p.?group.orValue('gateway.networking.k8s.io') == 'gateway.networking.k8s.io' && p.?kind.orValue('Gateway') == 'Gateway'
					  && p.?namespace.orValue('') == '\(_gatewayNamespace)' && p.name == variables.env)
					"""
				messageExpression: "'Routes attach to the Gateway ' + variables.env + ' in \(_gatewayNamespace) only.'"
				message:           "Routes attach to their environment's Gateway only."
			}]
		}
	}
}

_gatewayNamespace: "envoy-gateway-system"

// The reports controller scans existing routes in the background.
_policy: "tenant-http-routes": clusterRole: "kyverno:report-http-routes": {
	metadata: labels: "rbac.kyverno.io/aggregate-to-reports-controller": "true"
	rules: [{
		apiGroups: ["gateway.networking.k8s.io"]
		resources: ["httproutes"]
		verbs:     ["get", "list", "watch"]
	}]
}
