package policies

import (
	"encoding/json"
	"list"
	"strings"

	"github.com/homelab-selfuryon/platform-components/schema"
	teams_pkg "github.com/homelab-selfuryon/platform-components/teams"
)

// What every policy file sees as #ctx: plain values, derived once (#Derive). The policy files do not
// get the components themselves: unifying each of them with the whole component tree multiplied the
// render's memory.
#Context: {
	teams: [string]: teams_pkg.#Team
	registries: string
	wf: [string]: string
	issuer:         string
	domain:         string
	tenantNSRegex:  string
	image:          string
	tenantImages:   string
	whitelistsJSON: string
	wlResources: [string]: [string]: true
	nsRules: [string]: [...string]
	nsGroups: [...string]
	kustomizations: [string]: string
	privileged: [...string]
	helmReleases: [string]: {sa: string, ns: string}
}

// #Context from the cluster's config, the other components and the teams.
#Derive: {
	#cluster!: schema.#Cluster

	// Every other component of the cluster except `rbac` (built from the policies) and this one.
	#components!: schema.#Components
	#teams!: [string]: teams_pkg.#Team

	teams: #teams

	registries: json.Marshal(#cluster.security.allowedRegistries)
	wf:         #cluster.artifacts.workflows
	issuer:     #cluster.artifacts.issuer
	domain:     #cluster.domain

	// Namespaces of the teams: <team>-staging, <team>-prod, <team>-pr-<n>. Team names are [a-z0-9].
	tenantNSRegex: "^(" + strings.Join(list.SortStrings([for n, _ in #teams {n}]), "|") + ")-(staging|prod|pr-[0-9]+)$"
	image:         "\(#cluster.artifacts.registry)/"

	// Foreign images tenant pods may run: the workload images of platform operators (cnpg).
	tenantImages: json.Marshal(list.SortStrings([for _, c in #components for i in c.tenantImages {i}]))

	// username -> what the component's ServiceAccount may create at cluster scope; this component
	// included (it is not in #components, but its own Kustomization applies the policies as
	// component-kyverno-policies)
	let _self = {name: "kyverno-policies", privileged: false, whitelist: _selfWhitelist}
	let _whitelists = {
		for _, c in list.Concat([[for _, c in #components {c}], [_self]]) if !c.privileged && len(c.whitelist) > 0 {
			"system:serviceaccount:flux-system:component-\(c.name)": [for w in c.whitelist {
				g: w.apiGroup
				k: w.kind
				n: [for n in w.names {(#GlobRegex & {#g: n}).out}]
			}]
		}
	}

	// Heterogeneous values: handed to CEL as JSON (raw string, the regexes carry backslashes).
	whitelistsJSON: json.Marshal(_whitelists) & !~"'"

	// apiGroup -> resources the whitelists mention
	wlResources: {
		for _, c in #components if !c.privileged for w in c.whitelist {
			(w.apiGroup): (w.resource): true
		}

		// This component's own kinds, spelled out: derived from its whitelist they would make
		// component-whitelist depend on itself.
		"policies.kyverno.io": {
			validatingpolicies:      true
			imagevalidatingpolicies: true
			generatingpolicies:      true
			deletingpolicies:        true
		}
	}

	// username -> namespaces (regexes) a component may write to, for components that create their own
	nsRules: {
		for _, c in #components if !c.privileged && len(c.rbac.allowedNamespaces) > 0 {
			"system:serviceaccount:flux-system:component-\(c.name)": [for n in c.rbac.allowedNamespaces {(#GlobRegex & {#g: n}).out}]
		}
	}
	let _nsGroupSet = {
		for _, c in #components if !c.privileged && len(c.rbac.allowedNamespaces) > 0
		for r in list.Concat([c.rbac.clusterWide, [for _, rs in c.rbac.namespaced for r in rs {r}]])
		for g in r.apiGroups {(g): true}
	}
	nsGroups: list.SortStrings([for g, _ in _nsGroupSet {g}])

	// Kustomization name -> ServiceAccount
	kustomizations: {
		gitops:      "gitops-root"
		"argo-apps": "argo-apps"
		// Bootstrap-time sibling: the rbac set itself runs privileged.
		rbac: "flux-privileged"
		// This component (not in #components)
		"kyverno-policies": "component-kyverno-policies"
		for s in #cluster.sets {"set-\(s)": "gitops-root"}
		for _, c in #components {
			(c.name): [if c.privileged {"flux-privileged"}, "component-\(c.name)"][0]
		}
	}
	privileged: list.Concat([["rbac"], [for _, c in #components if c.privileged {c.name}]])

	// HelmRelease name -> ServiceAccount and namespace, for the variant A components
	helmReleases: {
		for _, c in #components if c.variant == "helmrelease" {
			(c.name): {
				sa: [if c.privileged {"flux-privileged"}, "component-\(c.name)"][0]
				ns: c.namespace
			}
		}
	}
}
