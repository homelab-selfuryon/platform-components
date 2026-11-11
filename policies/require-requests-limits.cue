package policies

_policy: "require-requests-limits": {
	#ctx: #Context

	global: validatingPolicy: {
		"require-requests-limits": spec: _pods & {
			validationActions: ["Audit"]
			matchConstraints: namespaceSelector: _tenantNS
			validations: [{
				expression: """
					variables.containers.all(c,
					  c.?resources.?requests.?cpu.hasValue() &&
					  c.?resources.?requests.?memory.hasValue() &&
					  c.?resources.?limits.?memory.hasValue())
					"""
				message: "Containers should set cpu and memory requests and a memory limit."
			}]
		}
	}
}
