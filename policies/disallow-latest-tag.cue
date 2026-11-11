package policies

_policy: "disallow-latest-tag": {
	#ctx: #Context

	global: validatingPolicy: {
		"disallow-latest-tag": spec: _pods & {
			validationActions: ["Deny"]
			validations: [{
				expression: "variables.containers.all(c, c.image.matches('^.+(:[^:/@]+(@sha256:[0-9a-f]{64})?|@sha256:[0-9a-f]{64})$') && !c.image.matches(':latest(@|$)'))"
				message:    "Images must be pinned to a tag other than latest, or to a digest."
			}]
		}
	}
}
