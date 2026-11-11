package policies

_policy: "secretobjects-only-in-system": {
	#ctx: #Context

	global: validatingPolicy: {
		"secretobjects-only-in-system": spec: {
			validationActions: ["Deny"]
			evaluation: background: enabled: true
			matchConstraints: resourceRules: [{
				apiGroups:   ["secrets-store.csi.x-k8s.io"]
				apiVersions: ["*"]
				operations:  ["CREATE", "UPDATE"]
				resources:   ["secretproviderclasses"]
			}]
			validations: [{
				expression: "size(object.spec.?secretObjects.orValue([])) == 0 || object.metadata.namespace.endsWith('-system')"
				message:    "Syncing secrets into Kubernetes Secrets (secretObjects) is for platform components in *-system namespaces: apps read secrets as files."
			}]
		}
	}
}
