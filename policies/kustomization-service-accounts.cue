package policies

import (
	"encoding/json"
)

_policy: "kustomization-service-accounts": {
	#ctx: #Context

	global: validatingPolicy: {
		"kustomization-service-accounts": spec: {
			validationActions: ["Deny"]
			evaluation: background: enabled: true
			matchConstraints: resourceRules: [{
				apiGroups:   ["kustomize.toolkit.fluxcd.io"]
				apiVersions: ["*"]
				operations:  ["CREATE", "UPDATE"]
				resources:   ["kustomizations"]
			}]
			variables: [
				{name: "expected", expression: json.Marshal(#ctx.kustomizations)},
				{name: "privileged", expression: json.Marshal(#ctx.privileged)},
				{name: "sa", expression: "object.spec.?serviceAccountName.orValue('')"},
			]
			validations: [
				{
					expression: "object.metadata.namespace == 'flux-system'"
					message:    "Kustomizations live in flux-system."
				},
				{
					expression: "object.metadata.name in variables.expected && variables.sa == variables.expected[object.metadata.name]"
					message:    "A Kustomization must run as the ServiceAccount of its component (component-<name>; flux-privileged for the listed privileged components; gitops-root for gitops and set-*; argo-apps for argo-apps)."
				},
				{
					expression: "variables.sa != 'flux-privileged' || object.metadata.name in variables.privileged"
					message:    "flux-privileged is for the privileged components only."
				},
				{
					expression: "!object.spec.?kubeConfig.hasValue() && !object.spec.sourceRef.?namespace.hasValue()"
					message:    "No remote clusters and no cross-namespace sources."
				},
			]
		}
	}
}
