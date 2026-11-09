package teams

import (
	"github.com/homelab-selfuryon/platform-components/schema"
)

let _verbs = ["get", "list", "watch", "create", "update", "patch", "delete"]

// Namespaced rules of a team's deploy ServiceAccounts: the kinds of #DeployKinds, nothing else.
#DeployRules: [for k in #DeployKinds {
	apiGroups: [k.group]
	resources: k.resources
	verbs:     _verbs
}]

// Onboarding of one team as a component of the `tenants` set (`team-<name>`):
//
//   <team>-staging, <team>-prod   Namespaces: Pod Security restricted, labels for admission and
//                                 the Gateways, ResourceQuota, ServiceAccount `deployer` with a
//                                 Role for the deployable kinds only, `view` for the team's group
//   argocd-system                 AppProjects `<team>` (staging, prod: sync as `deployer`) and
//                                 `<team>-preview`
//   cluster                       ServiceAccount and ClusterRole `<team>-preview-deployer`
//
// Preview namespaces `<team>-pr-<n>` do not exist ahead of time: Argo creates them. Argo syncs
// them as `argocd-system:<team>-preview-deployer`, whose ClusterRole covers the deployable kinds in every
// namespace and Namespace objects, which is far too much for RBAC alone: Kyverno restricts
// everything that ServiceAccount does to namespaces matching `<team>-pr-<n>` (policy
// `preview-deployer-scope`), labels such namespaces `env=preview` and generates their default-deny,
// LimitRange and quota. A team can not widen it: AppProject `<team>-preview` only allows
// destinations `<team>-pr-*`, the ServiceAccount and the policy are platform-owned.
#Tenants: {
	#team: #Team

	let _t = #team
	let _server = "https://kubernetes.default.svc"

	component: schema.#Component & {
		name:        "team-\(_t.name)"
		description: "Onboarding of the \(_t.name) team: namespaces, quotas, AppProjects, deploy ServiceAccounts."
		set:         "tenants"
		// Namespaces are created here (whitelisted by name), not by the rbac set.
		createNamespace: false
		targetNamespace: false
		network: policy: false

		rbac: {
			// Namespaces that do not exist yet when the RBAC is applied: cluster-wide rules, held
			// to the team's namespaces by admission (policy `component-namespaces`).
			clusterWide: [{
				apiGroups: [""]
				resources: ["serviceaccounts", "resourcequotas"]
				verbs:     _verbs
			}, {
				apiGroups: ["rbac.authorization.k8s.io"]
				resources: ["roles", "rolebindings"]
				verbs:     _verbs
			}, {
				// Roles of the team namespaces grant what #DeployRules lists.
				apiGroups:     ["rbac.authorization.k8s.io"]
				resources:     ["roles"]
				verbs:         ["escalate", "bind"]
				resourceNames: [_t.deployer]
			}, {
				apiGroups:     ["rbac.authorization.k8s.io"]
				resources:     ["clusterroles"]
				verbs:         ["bind"]
				resourceNames: ["view"]
			}]
			allowedNamespaces: [_t.namespaces.staging, _t.namespaces.prod, schema.#ArgoCDNamespace]
			namespaced: (schema.#ArgoCDNamespace): [{
				apiGroups: ["argoproj.io"]
				resources: ["appprojects"]
				verbs:     _verbs
			}, {
				apiGroups: [""]
				resources: ["serviceaccounts"]
				verbs:     _verbs
			}]
		}

		whitelist: [
			schema.#Namespace & {names: [_t.namespaces.staging, _t.namespaces.prod]},
			schema.#ClusterRole & {names: [_t.previewDeployer]},
			schema.#ClusterRoleBinding & {names: [_t.previewDeployer]},
		]

		manifests: global: {
			for env in ["staging", "prod"] {
				namespace: (_t.namespaces[env]): metadata: labels: {
					"pod-security.kubernetes.io/enforce":         "restricted"
					"pod-security.kubernetes.io/enforce-version": "latest"
					"pod-security.kubernetes.io/audit":           "restricted"
					"pod-security.kubernetes.io/warn":            "restricted"
					"\(schema.#Prefix)/team":                     _t.name
					"\(schema.#Prefix)/env":                      env
				}
			}

			// Preview: the SA's namespaced rights, everywhere; held to <team>-pr-<n> by admission.
			clusterRole: (_t.previewDeployer): rules: [
				for r in #DeployRules {r},
				{
					apiGroups: [""]
					resources: ["namespaces"]
					verbs:     ["get", "list", "watch", "create", "update", "patch", "delete"]
				},
			]
			clusterRoleBinding: (_t.previewDeployer): {
				roleRef:  {apiGroup: "rbac.authorization.k8s.io", kind: "ClusterRole", name: _t.previewDeployer}
				subjects: [{kind: "ServiceAccount", name: _t.previewDeployer, namespace: schema.#ArgoCDNamespace}]
			}
		}

		manifests: scoped: {
			for env in ["staging", "prod"] {
				let _ns = _t.namespaces[env]
				let _q = _t.quota[env]
				(_ns): {
					resourceQuota: "team-quota": spec: hard: {
						"requests.cpu":         _q.requestsCPU
						"requests.memory":      _q.requestsMemory
						"limits.memory":        _q.limitsMemory
						pods:                   _q.pods
						persistentvolumeclaims: _q.persistentVolumeClaims
						"requests.storage":     _q.requestsStorage
					}
					serviceAccount: (_t.deployer): automountServiceAccountToken: false
					role: (_t.deployer): rules:                                  #DeployRules
					roleBinding: (_t.deployer): {
						roleRef:  {apiGroup: "rbac.authorization.k8s.io", kind: "Role", name: _t.deployer}
						subjects: [{kind: "ServiceAccount", name: _t.deployer, namespace: _ns}]
					}
					// Read access for the team, without Secrets (`view` has none).
					roleBinding: "team-view": {
						roleRef:  {apiGroup: "rbac.authorization.k8s.io", kind: "ClusterRole", name: "view"}
						subjects: [{kind: "Group", apiGroup: "rbac.authorization.k8s.io", name: _t.group}]
					}
				}
			}

			(schema.#ArgoCDNamespace): {
				serviceAccount: (_t.previewDeployer): automountServiceAccountToken: false

				appProject: (_t.name): spec: {
					description:  "\(_t.name): staging and prod."
					sourceRepos:  _t.sourceRepos
					destinations: [for env in ["staging", "prod"] {server: _server, namespace: _t.namespaces[env]}]
					// Nothing at cluster scope.
					clusterResourceWhitelist:   []
					namespaceResourceWhitelist: [for k in #DeployKinds for kd in k.kinds {group: k.group, kind: kd}]
					// Sync as the namespace's own deploy ServiceAccount.
					destinationServiceAccounts: [for env in ["staging", "prod"] {
						server:                _server
						namespace:             _t.namespaces[env]
						defaultServiceAccount: _t.deployer
					}]
				}
				appProject: "\(_t.name)-preview": spec: {
					description:  "\(_t.name): preview environments (namespaces created by Argo)."
					sourceRepos:  _t.sourceRepos
					destinations: [{server: _server, namespace: _t.namespaces.previewPattern}]
					// Only the Namespace of the preview itself.
					clusterResourceWhitelist:   [{group: "", kind: "Namespace"}]
					namespaceResourceWhitelist: [for k in #DeployKinds for kd in k.kinds {group: k.group, kind: kd}]
					destinationServiceAccounts: [{
						server:                _server
						namespace:             _t.namespaces.previewPattern
						defaultServiceAccount: "\(schema.#ArgoCDNamespace):\(_t.previewDeployer)"
					}]
				}
			}
		}
	}
}
