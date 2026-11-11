package policies

_policy: "restrict-image-registries": {
	#ctx: #Context

	global: validatingPolicy: {
		"restrict-image-registries": spec: _pods & {
			validationActions: ["Deny"]
			variables:         [_, {name: "registries", expression: #ctx.registries}]
			validations: [{
				expression:        "variables.containers.all(c, variables.registries.exists(r, c.image.startsWith(r)))"
				messageExpression: "'Images must come from one of ' + variables.registries.join(', ') + ' and name the registry explicitly.'"
				message:           "Images must come from an allowed registry."
			}]
		}
	}
}
