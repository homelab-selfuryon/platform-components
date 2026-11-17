package policies

_policy: "tenant-image-signatures": {
	#ctx: #Context

	// Cosign keyless identity of the workflow that built an image, per environment. The
	// environment is the label of the namespace, which only the platform sets. Init containers run
	// the same way with the same rights, so their images are checked too; ephemeral containers are
	// refused altogether (tenant-deny-shell-access).
	let _images = "(images.containers + images.?initContainers.orValue([]))"

	global: imageValidatingPolicy: {
		"tenant-image-signatures-release": spec: _ivp & {
			matchConstraints: namespaceSelector: matchExpressions: [{key: _env, operator: "In", values: ["staging", "prod"]}]
			attestors: [{
				name: "release"
				cosign: keyless: identities: [{issuer: #ctx.issuer, subjectRegExp: #ctx.wf.appRelease}]
			}]
			validations: [{
				expression: "\(_images).map(image, verifyImageSignatures(image, [attestors.release])).all(e, e > 0)"
				message:    "Images in staging and prod must be signed by app-release.yaml of github-workflows."
			}]
		}
		"tenant-image-signatures-preview": spec: _ivp & {
			matchConstraints: namespaceSelector: matchExpressions: [{key: _env, operator: "In", values: ["preview"]}]
			attestors: [{
				name: "preview"
				cosign: keyless: identities: [{issuer: #ctx.issuer, subjectRegExp: #ctx.wf.appPreview}]
			}]
			validations: [{
				expression: "\(_images).map(image, verifyImageSignatures(image, [attestors.preview])).all(e, e > 0)"
				message:    "Images in preview namespaces must be signed by app-preview.yaml of github-workflows."
			}]
		}
	}
}
