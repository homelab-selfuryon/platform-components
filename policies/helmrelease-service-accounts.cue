package policies

import (
	"encoding/json"
)

_policy: "helmrelease-service-accounts": {
	#ctx: #Context

	global: validatingPolicy: {
		// Variant A: only the listed components ship a HelmRelease, in flux-system, installing
		// into their own namespace as their own ServiceAccount. Anything else could ask
		// helm-controller to act as flux-privileged.
		"helmrelease-service-accounts": spec: {
			validationActions: ["Deny"]
			evaluation: background: enabled: true
			matchConstraints: resourceRules: [{
				apiGroups:   ["helm.toolkit.fluxcd.io"]
				apiVersions: ["*"]
				operations:  ["CREATE", "UPDATE"]
				resources:   ["helmreleases"]
			}]
			variables: [
				{name: "expected", expression: json.Marshal(#ctx.helmReleases)},
				{name: "sa", expression: "object.spec.?serviceAccountName.orValue('')"},
			]
			validations: [
				{
					expression: "object.metadata.namespace == 'flux-system' && object.metadata.name in variables.expected"
					message:    "HelmReleases are a listed exception (variant A): only the listed components, in flux-system."
				},
				{
					expression: "variables.sa == variables.expected[object.metadata.name].sa"
					message:    "A HelmRelease must run as the ServiceAccount of its component."
				},
				{
					expression: "object.spec.?targetNamespace.orValue('') == variables.expected[object.metadata.name].ns && object.spec.?storageNamespace.orValue('') == variables.expected[object.metadata.name].ns"
					message:    "A HelmRelease installs into, and stores its release in, its component's namespace."
				},
				{
					expression: "!object.spec.?kubeConfig.hasValue() && !object.spec.?chartRef.?namespace.hasValue() && !object.spec.?chart.?spec.?sourceRef.?namespace.hasValue()"
					message:    "No remote clusters and no cross-namespace sources."
				},
			]
		}
	}
}
