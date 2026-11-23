package policies

_policy: "tenant-images-by-digest": {
	#ctx: #Context

	let _images = "(object.spec.containers + object.spec.?initContainers.orValue([]) + object.spec.?ephemeralContainers.orValue([])).map(c, c.image)"
	let _oldImages = "(oldObject.spec.containers + oldObject.spec.?initContainers.orValue([]) + oldObject.spec.?ephemeralContainers.orValue([])).map(c, c.image)"

	global: validatingPolicy: {
		"tenant-images-by-digest": spec: _pods & {
			validationActions: ["Deny"]
			matchConstraints: namespaceSelector: _tenantNS
			// The first variable is _pods' `containers`.
			variables: [{}, {
				name:       "platformImages"
				expression: #ctx.tenantImages
			}, {
				// An update that keeps the pod's images (labels, annotations, status: what an
				// operator patches) is not judged again. Otherwise a pod started with an image that
				// has since left tenantImages (a new digest of an operator image) can no longer be
				// touched, and its operator stops reconciling until the pod is gone. On CREATE oldObject is
				// null, and in the CLI and background scans an empty object.
				name:       "imagesUnchanged"
				expression: "oldObject != null && has(oldObject.spec) && \(_images) == \(_oldImages)"
			}]
			validations: [{
				expression: "variables.imagesUnchanged || variables.containers.all(c, (c.image.startsWith('\(#ctx.image)') && c.image.matches('@sha256:[0-9a-f]{64}$')) || c.image in variables.platformImages)"
				message:    "Tenant images must come from \(#ctx.image) and be pinned by digest (@sha256:...), or be one of the platform operators' images (tenantImages)."
			}]
		}
	}
}
