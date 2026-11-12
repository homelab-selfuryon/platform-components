package policies

import (
	"github.com/homelab-selfuryon/platform-components/schema"
	"github.com/homelab-selfuryon/platform-components/teams"
)

// Kyverno CEL policies (policies.kyverno.io/v1), all Enforce unless a rule says Audit. Lives in the
// `policy` set: the CRDs come with Kyverno in `system`. One file per policy, named like it.
//
//   Workloads (every namespace)
//     disallow-latest-tag, restrict-image-registries, disallow-default-namespace,
//     restrict-service-exposure, require-requests-limits (Audit), cleanup-finished-pods
//   Tenant namespaces (label homelab-selfuryon.github.io/team)
//     tenant-images-by-digest        images ghcr.io/homelab-selfuryon/*@sha256, plus operators' tenantImages
//     tenant-image-signatures        cosign keyless identity per environment (ImageValidatingPolicy):
//                                    staging/prod: app-release.yaml, preview: app-preview.yaml
//     tenant-deny-shell-access       no exec, attach, port-forward, ephemeral containers
//     tenant-deny-sa-token-secrets   no legacy ServiceAccount token Secrets
//     tenant-deny-cluster-scoped     no webhooks, CRDs, ClusterRoles, CiliumClusterwideNetworkPolicies
//                                    from ServiceAccounts of tenant namespaces
//     tenant-namespace-labels        Pod Security restricted, name matches team and environment
//     tenant-postgres-clusters       CNPG Clusters: images from the platform catalog, no superuser
//     tenant-network-policies        CiliumNetworkPolicies: pods of the teams and kube-dns, FQDNs,
//                                    kube-apiserver; no entities, CIDRs or reserved labels
//     tenant-http-routes             HTTPRoutes: the team's own host names, its environment's Gateway
//     tenant-defaults                tenant-default-deny / tenant-default-limits, generated per
//                                    tenant namespace; preview-quota-<team> per preview namespace
//     preview-deployer-scope         the preview deploy ServiceAccount acts in <team>-pr-<n> only;
//                                    its Namespaces carry no platform labels besides team and env
//   Platform
//     component-whitelist            names of the cluster-scoped objects a component ServiceAccount creates
//     component-namespaces           namespaces a component ServiceAccount (teams) writes to
//     kustomization-service-accounts which ServiceAccount a Flux Kustomization may use
//     helmrelease-service-accounts   HelmReleases: listed components only, own ServiceAccount and namespace
//     secretobjects-only-in-system   SecretProviderClass `secretObjects` in `*-system` namespaces only
//
// A policy file adds one entry to _policy: cluster-scoped objects under `global` (the keys of
// schema.#GlobalTypes: validatingPolicy, generatingPolicy, clusterRole, ...), built from #ctx:
//
//   _policy: "<name>": {
//   	#ctx: #Context
//   	global: validatingPolicy: "<name>": spec: {...}
//   }
_policy: [string]: {
	#ctx:   #Context
	global: {...}
}

#Policies: {
	#cluster: schema.#Cluster

	// Every other component of the cluster except `rbac` (built from this one) and this one.
	#components: schema.#Components
	#teams: [string]: teams.#Team

	// Aliases: inside the literal below `#teams: #teams` would refer to itself.
	let _cluster = #cluster
	let _components = #components
	let _teams = #teams
	let _derived = #Derive & {
		#cluster:    _cluster
		#components: _components
		#teams:      _teams
	}

	// Regular fields only (no #components): see #Context.
	let _ctx = #Context & {for k, v in _derived {(k): v}}

	component: schema.#Component & {
		name:        "kyverno-policies"
		description: "Kyverno CEL policies: workloads, tenants, component ServiceAccounts."
		set:         "policy"
		dependsOn:   ["kyverno"]

		manifests: global: {
			for _, p in _policy {
				(p & {#ctx: _ctx}).global
			}
		}

		whitelist: _selfWhitelist
	}
}

// Its own policy kinds: any name. With exact names a new policy is refused by the
// component-whitelist still running in the cluster (it does not know the name yet) and the
// whole set stops. This component is the only source of policies and the render is reviewed
// here; the ClusterRoles keep exact names.
_selfWhitelist: [
	schema.#ClusterRole & {names: ["kyverno:generate-tenant-defaults", "kyverno:cleanup-pods", "kyverno:report-postgres-clusters"]},
	for key, spec in {
		validatingPolicy:      {kind: "ValidatingPolicy", resource: "validatingpolicies"}
		imageValidatingPolicy: {kind: "ImageValidatingPolicy", resource: "imagevalidatingpolicies"}
		generatingPolicy:      {kind: "GeneratingPolicy", resource: "generatingpolicies"}
		deletingPolicy:        {kind: "DeletingPolicy", resource: "deletingpolicies"}
	} {
		schema.#Allow & {
			apiGroup: "policies.kyverno.io"
			kind:     spec.kind
			resource: spec.resource
			names:    ["*"]
		}
	},
]
