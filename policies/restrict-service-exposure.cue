package policies

_policy: "restrict-service-exposure": {
	#ctx: #Context

	global: validatingPolicy: {
		"restrict-service-exposure": spec: {
			validationActions: ["Deny"]
			evaluation: background: enabled: true
			matchConstraints: resourceRules: [{
				apiGroups:   [""]
				apiVersions: ["v1"]
				operations:  ["CREATE", "UPDATE"]
				resources:   ["services"]
			}]
			validations: [{
				expression: """
					!(object.spec.?type.orValue('ClusterIP') in ['LoadBalancer', 'NodePort'])
					|| object.metadata.?namespace.orValue('').endsWith('-system')
					|| namespaceObject.?metadata.?labels.orValue({}).exists(k, k == '\(_expose)' && namespaceObject.metadata.labels[k] == 'true')
					"""
				message: "LoadBalancer/NodePort Services expose the node's addresses: label the namespace \(_expose)=true to allow them."
			}]
		}
	}
}
