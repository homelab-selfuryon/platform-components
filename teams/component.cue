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
//   argocd-<team>                 Namespace of the team's staging and prod Applications (written by
//                                 Flux `argo-apps`, status by the Argo controller); the team's
//                                 group reads Applications and events there, and nothing else
//   argocd-system                 AppProjects `<team>` (staging, prod: sync as `deployer`; source
//                                 namespace argocd-<team>) and `<team>-preview` (its
//                                 ApplicationSet and Applications stay in argocd-system)
//   cluster                       ServiceAccount and ClusterRole `<team>-preview-deployer`
//
// Preview namespaces `<team>-pr-<n>` do not exist ahead of time: Argo creates them. Argo syncs
// them as `argocd-system:<team>-preview-deployer`, whose ClusterRole covers the deployable kinds in every
// namespace and Namespace objects, which is far too much for RBAC alone: Kyverno restricts
// everything that ServiceAccount does to namespaces matching `<team>-pr-<n>` (policy
// `preview-deployer-scope`), labels such namespaces `env=preview` and generates their default-deny,
// LimitRange, quota and a `view` RoleBinding for the team's group. A team can not widen it: AppProject `<team>-preview` only allows
// destinations `<team>-pr-*`, the ServiceAccount and the policy are platform-owned.
// Argo never deletes the namespaces it creates: `cleanup-preview-namespaces` removes them once no
// Application points at them.
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
			allowedNamespaces: [_t.namespaces.staging, _t.namespaces.prod, _t.namespaces.argocd, schema.#ArgoCDNamespace]
			namespaced: (schema.#ArgoCDNamespace): [{
				apiGroups: ["argoproj.io"]
				resources: ["appprojects"]
				verbs:     _verbs
			}, {
				apiGroups: [""]
				resources: ["serviceaccounts"]
				verbs:     _verbs
			}]
			// What the Roles there grant (a Role can only grant what its author holds).
			namespaced: (_t.namespaces.argocd): [{
				apiGroups: ["argoproj.io"]
				resources: ["applications"]
				verbs:     _verbs
			}, {
				apiGroups: [""]
				resources: ["events"]
				verbs:     ["get", "list", "watch", "create", "patch"]
			}, {
				// Flux dry-runs every object before applying any: without `bind` the API server looks
				// up the Role a RoleBinding names to check for escalation, and it does not exist yet.
				apiGroups:     ["rbac.authorization.k8s.io"]
				resources:     ["roles"]
				verbs:         ["bind"]
				resourceNames: ["argo-apps", "argocd-application-controller", "team-view"]
			}]
		}

		whitelist: [
			schema.#Namespace & {names: [_t.namespaces.staging, _t.namespaces.prod, _t.namespaces.argocd]},
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

			// No team or env label: not a tenant namespace (no workloads, tenant policies do not apply).
			namespace: (_t.namespaces.argocd): metadata: labels: {
				"pod-security.kubernetes.io/enforce":         "restricted"
				"pod-security.kubernetes.io/enforce-version": "latest"
				"pod-security.kubernetes.io/audit":           "restricted"
				"pod-security.kubernetes.io/warn":            "restricted"
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

			(_t.namespaces.argocd): {
				// Flux (Kustomization `argo-apps`, gitops) applies the Applications.
				role: "argo-apps": rules: [{
					apiGroups: ["argoproj.io"]
					resources: ["applications"]
					verbs:     _verbs
				}]
				roleBinding: "argo-apps": {
					roleRef:  {apiGroup: "rbac.authorization.k8s.io", kind: "Role", name: "argo-apps"}
					subjects: [{kind: "ServiceAccount", name: "argo-apps", namespace: "flux-system"}]
				}
				// The Argo controller reads Applications cluster-wide (its ClusterRole) and writes
				// their status and events here.
				role: "argocd-application-controller": rules: [{
					apiGroups: ["argoproj.io"]
					resources: ["applications"]
					verbs:     ["get", "list", "watch", "update", "patch"]
				}, {
					apiGroups: [""]
					resources: ["events"]
					verbs:     ["create", "patch"]
				}]
				roleBinding: "argocd-application-controller": {
					roleRef:  {apiGroup: "rbac.authorization.k8s.io", kind: "Role", name: "argocd-application-controller"}
					subjects: [{kind: "ServiceAccount", name: "argocd-application-controller", namespace: schema.#ArgoCDNamespace}]
				}
				// The team sees its Applications (sync, health, history) and their events.
				role: "team-view": rules: [{
					apiGroups: ["argoproj.io"]
					resources: ["applications"]
					verbs:     ["get", "list", "watch"]
				}, {
					apiGroups: [""]
					resources: ["events"]
					verbs:     ["get", "list", "watch"]
				}]
				roleBinding: "team-view": {
					roleRef:  {apiGroup: "rbac.authorization.k8s.io", kind: "Role", name: "team-view"}
					subjects: [{kind: "Group", apiGroup: "rbac.authorization.k8s.io", name: _t.group}]
				}
			}

			(schema.#ArgoCDNamespace): {
				serviceAccount: (_t.previewDeployer): automountServiceAccountToken: false

				appProject: (_t.name): spec: {
					description: "\(_t.name): staging and prod."
					sourceRepos: _t.sourceRepos
					// Applications of this project may live there. Never the control plane namespace
					// (argocd-system): Applications there may use any project anyway.
					sourceNamespaces: [_t.namespaces.argocd]
					destinations:     [for env in ["staging", "prod"] {server: _server, namespace: _t.namespaces[env]}]
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
