package policies

_policy: "tenant-deny-cluster-scoped": {
	#ctx: #Context

	global: validatingPolicy: {
		// Webhooks, CRDs, ClusterRoles and cluster-wide network policies are the platform's.
		"tenant-deny-cluster-scoped": spec: {
			validationActions: ["Deny"]
			// Reads request.userInfo, which a background scan does not have: admission only.
			evaluation: background: enabled: false
			matchConditions: [{
				name:       "tenant-serviceaccount"
				expression: "request.userInfo.username.matches('^system:serviceaccount:[a-z0-9]+-(staging|prod|pr-[0-9]+):')"
			}]
			matchConstraints: resourceRules: [
				{
					apiGroups:   ["admissionregistration.k8s.io"]
					apiVersions: ["*"]
					operations:  ["CREATE", "UPDATE"]
					resources:   ["validatingwebhookconfigurations", "mutatingwebhookconfigurations", "validatingadmissionpolicies", "validatingadmissionpolicybindings"]
				},
				{
					apiGroups:   ["apiextensions.k8s.io"]
					apiVersions: ["*"]
					operations:  ["CREATE", "UPDATE"]
					resources:   ["customresourcedefinitions"]
				},
				{
					apiGroups:   ["rbac.authorization.k8s.io"]
					apiVersions: ["*"]
					operations:  ["CREATE", "UPDATE"]
					resources:   ["clusterroles", "clusterrolebindings"]
				},
				{
					apiGroups:   ["cilium.io"]
					apiVersions: ["*"]
					operations:  ["CREATE", "UPDATE"]
					resources:   ["ciliumclusterwidenetworkpolicies"]
				},
			]
			validations: [{
				expression: "false"
				message:    "Webhooks, CRDs, ClusterRoles and CiliumClusterwideNetworkPolicies can not be created from tenant namespaces."
			}]
		}
	}
}
