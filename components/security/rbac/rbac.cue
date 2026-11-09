package rbac

import (
	"list"
	"strings"

	"github.com/homelab-selfuryon/platform-components/schema"
)

let _verbs = ["get", "list", "watch", "create", "update", "patch", "delete"]

// The `rbac` set: everything the other components' Flux ServiceAccounts need, derived from the
// component definitions (the whitelists, namespaces, Pod Security levels):
//
//   - the namespaces of all components (a component cannot create or relabel its own namespace),
//   - ServiceAccount `component-<name>` in flux-system for every component that is not privileged,
//   - a Role with all verbs on all namespaced resources in the component's namespaces (or the
//     component's own rules, `rbac.namespaced`), bound to the ServiceAccount,
//   - a ClusterRole from the whitelist: verbs on exactly the whitelisted kinds, plus `escalate` and
//     `bind` on exactly the whitelisted ClusterRoles (create can be restricted by name for those),
//   - the ServiceAccount `argo-apps`, which the Kustomization of the same name applies the
//     Applications as (its Role in argocd-system comes with the argocd component).
//
// Names are enforced by admission (policies set), kinds by these roles, the render by
// `cue cmd check`. `flux-privileged` and `gitops-root` come from bootstrap, not from here.
#RBAC: {
	#cluster: schema.#Cluster

	// Every component of the cluster except this one.
	#components: schema.#Components

	let _all = #components

	// Unique namespaces to create, with the strictest Pod Security level their components declare.
	let _namespaces = {
		for _, c in _all if c.namespace != _|_ if c.createNamespace {
			(c.namespace): {level: c.psa.level, component: c.name}
		}
	}

	component: schema.#Component & {
		name:            "rbac"
		description:     "Namespaces, ServiceAccounts and RBAC of the other components, from their definitions."
		namespace:       "flux-system"
		set:             "rbac"
		createNamespace: false
		targetNamespace: false
		network: policy: false
		privileged: true
		reason:     "Creates the ServiceAccounts and roles every other component's Kustomization runs with: nothing below it can create them."

		manifests: global: {
			for ns, n in _namespaces {
				namespace: (ns): metadata: labels: {
					"pod-security.kubernetes.io/enforce":         n.level
					"pod-security.kubernetes.io/enforce-version": "latest"
					"pod-security.kubernetes.io/audit":           "restricted"
					"pod-security.kubernetes.io/warn":            "restricted"
					"\(schema.#Prefix)/component":                n.component
				}
			}

			for _, c in _all if !c.privileged {
				let _cl = [for w in c.whitelist {w}]
				let _crNames = list.Concat([[for w in _cl if w.kind == "ClusterRole" for n in w.names {n}], []])
				let _hasCRB = len([for w in _cl if w.kind == "ClusterRoleBinding" {w}]) > 0
				let _bindNames = list.Concat([_crNames, [for w in _cl for b in w.bind {b}]])
				let _rules = list.Concat([
					[for w in _cl {
						apiGroups: [w.apiGroup]
						resources: [w.resource]
						verbs:     _verbs
					}],
					[if len(_crNames) > 0 {
						apiGroups:     ["rbac.authorization.k8s.io"]
						resources:     ["clusterroles"]
						verbs:         ["escalate"]
						resourceNames: _crNames
					}],
					[if len(_bindNames) > 0 && (len(_crNames) > 0 || _hasCRB) {
						apiGroups:     ["rbac.authorization.k8s.io"]
						resources:     ["clusterroles"]
						verbs:         ["bind"]
						resourceNames: _bindNames
					}],
					c.rbac.clusterWide,
				])
				if len(_rules) > 0 {
					clusterRole: "component-\(c.name)": rules: _rules
					clusterRoleBinding: "component-\(c.name)": {
						roleRef:  {apiGroup: "rbac.authorization.k8s.io", kind: "ClusterRole", name: "component-\(c.name)"}
						subjects: [{kind: "ServiceAccount", name: "component-\(c.name)", namespace: "flux-system"}]
					}
				}

				// RBAC kinds are restricted by exact names (escalate/bind take resourceNames).
				for w in _cl if w.apiGroup == "rbac.authorization.k8s.io" for n in w.names {
					_exact: (c.name): (n): true & !strings.Contains(n, "*")
				}
			}
		}

		manifests: scoped: "flux-system": {
			serviceAccount: "argo-apps": automountServiceAccountToken: false
			for _, c in _all if !c.privileged {
				serviceAccount: "component-\(c.name)": automountServiceAccountToken: false
			}
		}

		// Namespaced rights: a Role per namespace the component writes to.
		for _, c in _all if !c.privileged {
			let _own = list.Concat([[if c.namespace != _|_ {c.namespace}], c.extraNamespaces, [for k, _ in c.rbac.namespaced {k}]])
			for ns in _own {
				manifests: scoped: (ns): {
					role: "component-\(c.name)": rules: [
						if c.rbac.namespaced[ns] != _|_ {c.rbac.namespaced[ns]}
						if c.rbac.namespaced[ns] == _|_ {[{apiGroups: ["*"], resources: ["*"], verbs: ["*"]}]}
					][0]
					roleBinding: "component-\(c.name)": {
						roleRef:  {apiGroup: "rbac.authorization.k8s.io", kind: "Role", name: "component-\(c.name)"}
						subjects: [{kind: "ServiceAccount", name: "component-\(c.name)", namespace: "flux-system"}]
					}
				}
			}
		}

		whitelist: [
			schema.#Namespace & {names: ["*"]},
			schema.#ClusterRole & {names: ["component-*"]},
			schema.#ClusterRoleBinding & {names: ["component-*"]},
		]
	}
}
