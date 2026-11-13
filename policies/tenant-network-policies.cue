package policies

// CiliumNetworkPolicies of the teams: only what platform-kit renders. Cilium adds allow rules
// together, so without this a team's policy could open what tenant-default-deny closes: the node
// and the kube-apiserver for everything, the world, other platform namespaces.
//
//   ingress  fromEndpoints (pods, any namespace: the Gateway's proxies, the callers), toPorts
//   egress   toEndpoints in the teams' namespaces (or kube-dns), toFQDNs by matchName,
//            toEntities kube-apiserver, toPorts
//
// Endpoint selectors: matchLabels only, keys `k8s:...` or `<prefix>/<name>`: an unprefixed key like
// `host` would match Cilium's reserved labels (reserved:host, reserved:world), and
// io.cilium.* keys select by namespace labels or ServiceAccount.
_policy: "tenant-network-policies": {
	#ctx: #Context

	let _ns = "k8s:io.kubernetes.pod.namespace"

	global: validatingPolicy: {
		"tenant-network-policies": spec: {
			validationActions: ["Deny"]
			evaluation: background: enabled: true
			matchConstraints: {
				namespaceSelector: _tenantNS
				resourceRules: [{
					apiGroups:   ["cilium.io"]
					apiVersions: ["*"]
					operations:  ["CREATE", "UPDATE"]
					resources:   ["ciliumnetworkpolicies"]
				}]
			}
			variables: [
				{name: "spec", expression: "object.?spec.orValue({})"},
				{name: "ingress", expression: "variables.spec.?ingress.orValue([])"},
				{name: "egress", expression: "variables.spec.?egress.orValue([])"},
			]
			validations: [{
				expression: "!has(object.specs) && variables.spec.all(k, k in ['endpointSelector', 'ingress', 'egress', 'description'])"
				message:    "Tenant CiliumNetworkPolicies have one `spec` with endpointSelector, ingress and egress only (no deny rules, no enableDefaultDeny)."
			}, {
				expression: "variables.ingress.all(r, r.all(k, k in ['fromEndpoints', 'toPorts']))"
				message:    "Tenant ingress rules allow fromEndpoints (pods) with toPorts only: no entities, CIDRs, nodes or groups."
			}, {
				expression: "variables.egress.all(r, r.all(k, k in ['toEndpoints', 'toFQDNs', 'toEntities', 'toPorts']) && r.?toEntities.orValue([]).all(e, e == 'kube-apiserver') && r.?toFQDNs.orValue([]).all(f, f.all(k, k == 'matchName')))"
				message:    "Tenant egress rules allow toEndpoints, toFQDNs (matchName), toEntities kube-apiserver and toPorts only."
			}, {
				expression: """
					(variables.ingress.map(r, r.?fromEndpoints.orValue([])) + variables.egress.map(r, r.?toEndpoints.orValue([]))).all(ss, ss.all(s,
					  s.all(k, k == 'matchLabels') && s.?matchLabels.orValue({}).all(k,
					    k.matches('^(k8s:[A-Za-z0-9._/-]+|[a-z0-9.-]+/[A-Za-z0-9._-]+)$') && !k.contains('io.cilium.'))))
					"""
				message: "Endpoint selectors take matchLabels with keys `k8s:<label>` or `<prefix>/<name>` only (no reserved:, io.cilium.* or matchExpressions)."
			}, {
				expression: """
					variables.egress.all(r, r.?toEndpoints.orValue([]).all(s,
					  !('\(_ns)' in s.?matchLabels.orValue({}))
					  || s.matchLabels['\(_ns)'].matches('\(#ctx.tenantNSRegex)')
					  || (s.matchLabels['\(_ns)'] == 'kube-system' && s.matchLabels[?'k8s:k8s-app'].orValue('') == 'kube-dns')))
					"""
				message: "Egress to pods goes to the teams' namespaces (<team>-staging, -prod, -pr-<n>) or to kube-dns."
			}]
		}
	}
}

// The reports controller scans existing policies in the background.
_policy: "tenant-network-policies": clusterRole: "kyverno:report-cilium-network-policies": {
	metadata: labels: "rbac.kyverno.io/aggregate-to-reports-controller": "true"
	rules: [{
		apiGroups: ["cilium.io"]
		resources: ["ciliumnetworkpolicies"]
		verbs:     ["get", "list", "watch"]
	}]
}
