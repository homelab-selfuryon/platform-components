package policies

import (
	"encoding/json"
	"list"
	"github.com/homelab-selfuryon/platform-components/schema"
	"github.com/homelab-selfuryon/platform-components/teams"
)

_policy: "preview-deployer-scope": {
	#ctx: #Context

	global: validatingPolicy: {
		// The preview deploy ServiceAccount of each team acts in <team>-pr-<n> namespaces only.
		if len(#ctx.teams) > 0 {
			"preview-deployer-scope": spec: {
				validationActions: ["Deny"]
				// Reads request.userInfo, which a background scan does not have: admission only.
				evaluation: background: enabled: false
				matchConditions: [{
					name:       "preview-deployer"
					expression: "request.userInfo.username in \(json.Marshal([for _, t in #ctx.teams {"system:serviceaccount:\(schema.#ArgoCDNamespace):\(t.previewDeployer)"}]))"
				}]
				matchConstraints: resourceRules: [{
					apiGroups:   list.SortStrings([for g, _ in {for k in teams.#DeployKinds {(k.group): true}} {g}])
					apiVersions: ["*"]
					operations:  ["CREATE", "UPDATE", "DELETE"]
					resources:   ["*"]
				}]
				variables: [
					{name: "allowed", expression: json.Marshal({for _, t in #ctx.teams {"system:serviceaccount:\(schema.#ArgoCDNamespace):\(t.previewDeployer)": t.namespaces.previewRegex}})},
					{name: "target", expression: "request.operation == 'DELETE' ? oldObject : object"},
					{name: "ns", expression: "variables.target.kind == 'Namespace' ? variables.target.metadata.name : variables.target.metadata.?namespace.orValue('')"},
				]
				validations: [{
					expression: "variables.ns.matches(variables.allowed[request.userInfo.username])"
					message:    "The preview deploy ServiceAccount may only act in its team's preview namespaces (<team>-pr-<n>)."
				}, {
					// Argo creates the namespace as this ServiceAccount (managedNamespaceMetadata), and
					// so could an artifact. Policies and OpenBao trust the platform's labels on it
					// (expose, team, env): only team and env, and Pod Security restricted, are allowed.
					expression: """
						variables.target.kind != 'Namespace' || request.operation == 'DELETE'
						|| object.metadata.?labels.orValue({}).all(k,
						     (!k.startsWith('\(schema.#Prefix)/') || k in ['\(_team)', '\(_env)'])
						     && (!k.startsWith('pod-security.kubernetes.io/') || object.metadata.labels[k] in ['restricted', 'latest']))
						"""
					message: "Preview namespaces carry only the platform labels team and env, and Pod Security restricted."
				}]
			}
		}
	}
}
