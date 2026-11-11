package policies

_policy: "tenant-images-by-digest": {
	#ctx: #Context

	global: validatingPolicy: {
		"tenant-images-by-digest": spec: _pods & {
			validationActions: ["Deny"]
			matchConstraints: namespaceSelector: _tenantNS
			// The first variable is _pods' `containers`.
			variables: [{}, {name: "platformImages", expression: #ctx.tenantImages}]
			validations: [{
				expression: "variables.containers.all(c, (c.image.startsWith('\(#ctx.image)') && c.image.matches('@sha256:[0-9a-f]{64}$')) || c.image in variables.platformImages)"
				message:    "Tenant images must come from \(#ctx.image) and be pinned by digest (@sha256:...), or be one of the platform operators' images (tenantImages)."
			}]
		}
	}
}
