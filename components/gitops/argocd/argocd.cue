package argocd

import (
	"strings"

	"github.com/homelab-selfuryon/platform-components/schema"
)

#namespace: schema.#ArgoCDNamespace

// Argo CD for tenants: it syncs the apps' manifest artifacts (OCI, by digest) into their
// namespaces, impersonating the team's deploy ServiceAccount. Platform components are not
// delivered by it (Flux does that).
//
// Hardening: no API server or UI (core mode: no local admin, no exec, no tokens to leak), no
// config management plugins, no Dex, no notifications; sync impersonation on; the application
// controller reads a fixed set of kinds (no Secrets; `resource.respectRBAC` skips the rest) and
// may impersonate only the deploy ServiceAccounts; the `default` AppProject allows nothing.
#ArgoCD: {
	#cluster: schema.#Cluster
	#ref:     schema.#Ref
	let _ref = #ref

	// Names of the ServiceAccounts Argo may impersonate (one per team and environment kind).
	#impersonate: [...string]

	// Namespaces of the teams' Applications (`argocd-<team>`, apps in any namespace): a team reads
	// its own there. Their AppProjects stay here and name them in `sourceNamespaces`; the
	// controller's write access there comes with each team (teams/component.cue). ApplicationSets
	// stay in this namespace only: in more than one, the ApplicationSet controller watches Secrets
	// cluster-wide.
	#appNamespaces: [...string]

	component: schema.#Component & {
		name:        "argocd"
		description: "Argo CD for tenant manifests (headless, sync impersonation)."
		namespace:   #namespace
		set:         "platform"

		chart: schema.#Chart & {
			#ref: _ref
			kind: "oci"
			url:  "oci://ghcr.io/argoproj/argo-helm"
			name: "argo-cd"
		}
		values: {
			fullnameOverride: "argocd"
			crds: {
				install: true
				keep:    true
			}
			global: networkPolicy: create: false
			server: enabled:        false
			dex: enabled:           false
			notifications: enabled: false
			redis: enabled:         true
			"redis-ha": enabled:    false
			configs: {
				cm: {
					"admin.enabled":                          "false"
					"users.anonymous.enabled":                "false"
					"exec.enabled":                           "false"
					"application.sync.impersonation.enabled": "true"
					// The controller caches every kind in the cluster unless told otherwise; its ClusterRole below
					// reads only tenant kinds, so without this the cache fails on the first forbidden kind
					// (Secrets, Flux) and no Application gets a live state. `strict`: skip a kind only when a
					// SelfSubjectAccessReview confirms the list is denied (a passing 401 does not drop a kind).
					"resource.respectRBAC": "strict"
				}
				params: "application.namespaces": strings.Join(#appNamespaces, ",")
				// No config management plugins.
				cmp: create: false
			}
			controller: {
				replicas: 1
				// Instead of the chart's `*` on everything: read the kinds tenants may deploy, and
				// impersonate the deploy ServiceAccounts. No Secrets.
				clusterRoleRules: {
					enabled: true
					rules: [{
						apiGroups: [""]
						resources: ["pods", "services", "serviceaccounts", "configmaps", "namespaces", "persistentvolumeclaims", "resourcequotas", "limitranges", "endpoints", "events"]
						verbs:     ["get", "list", "watch"]
					}, {
						apiGroups: ["apps", "batch", "policy", "autoscaling", "networking.k8s.io", "discovery.k8s.io", "rbac.authorization.k8s.io", "gateway.networking.k8s.io", "cilium.io", "postgresql.cnpg.io", "secrets-store.csi.x-k8s.io", "argoproj.io", "apiextensions.k8s.io"]
						resources: ["*"]
						verbs:     ["get", "list", "watch"]
					}, {
						apiGroups:     [""]
						resources:     ["serviceaccounts"]
						verbs:         ["impersonate"]
						resourceNames: #impersonate
					}]
				}
			}
			// ApplicationSet controller: the preview ApplicationSets (pull request generator), in
			// argocd-system only (no `allowAnyNamespace`).
			applicationSet: replicas: 1
			repoServer: replicas:     1
		}

		manifests: scoped: (#namespace): {
			// The Kustomization `argo-apps` (gitops) applies Applications and ApplicationSets as this
			// ServiceAccount (created in flux-system by the `rbac` set), nothing else in this namespace.
			role: "argo-apps": rules: [{
				apiGroups: ["argoproj.io"]
				resources: ["applications", "applicationsets"]
				verbs:     ["get", "list", "watch", "create", "update", "patch", "delete"]
			}]
			roleBinding: "argo-apps": {
				roleRef:  {apiGroup: "rbac.authorization.k8s.io", kind: "Role", name: "argo-apps"}
				subjects: [{kind: "ServiceAccount", name: "argo-apps", namespace: "flux-system"}]
			}
		}
		// The built-in `default` project allows everything: lock it, teams have their own.
		manifests: scoped: (#namespace): appProject: default: spec: {
			description:                "Locked: tenants use their team's projects."
			sourceRepos:                []
			destinations:               []
			clusterResourceWhitelist:   []
			namespaceResourceWhitelist: []
		}

		network: {
			ingress: [schema.Net.sameNamespaceIn]
			egress: [
				schema.Net.apiserverOut,
				schema.Net.sameNamespaceOut,
				// OCI registry (manifest artifacts), GitHub API (preview pull request generator)
				schema.Net.world & schema.Net.https,
			]
		}

		whitelist: [
			schema.#CRD & {names: ["applications.argoproj.io", "applicationsets.argoproj.io", "appprojects.argoproj.io"]},
			schema.#ClusterRole & {names: ["argocd-application-controller"]},
			schema.#ClusterRoleBinding & {names: ["argocd-application-controller"]},
		]
	}
}
