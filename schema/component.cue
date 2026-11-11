package schema

import "strings"

// A Helm chart a component is rendered from.
#Chart: {
	// helm: classic HTTP Helm repository (url = repository)
	// oci:  chart stored as an OCI artifact (url = repository without the chart name)
	// git:  chart inside a Git repository at a tag (url = repository, path = chart directory)
	kind!:    "helm" | "oci" | "git"
	url!:     string
	name!:    string
	version?: string
	// Content digest of the OCI chart (sha256:...), when the registry has one. Helm verifies it.
	digest?: =~"^sha256:[0-9a-f]{64}$"
	if kind == "git" {
		path!: string
	}

	// Helm release name (also the name prefix most charts use). Default: the component name.
	releaseName?: string
	// Install the chart's CRDs (`helm template --include-crds`). Components that
	// manage their CRDs through a chart value turn this off.
	includeCRDs: *false | bool
	// Resolved version (and digest) of the component, see registry.#Resolve. Sets version and digest.
	#ref?: #Ref
	if #ref != _|_ {
		version: #ref.version
		if #ref.digest != _|_ {
			digest: #ref.digest
		}
	}
}

// What a component may create at cluster scope. The render is checked against it
// (`cue cmd check`), RBAC for the component's Flux ServiceAccount is generated from
// it (kinds, `rbac` set) and an admission policy enforces the names (`policy` set).
#Allow: {
	// "" for the core group
	apiGroup: string
	kind!:    string
	// Plural lower-case resource name, as in RBAC rules.
	resource!: string
	// Exact names, or globs with `*` (matched like shell globs). RBAC kinds take exact names only
	// (their escalation checks are restricted by resourceName).
	names!: [...string] & [_, ...]
	// ClusterRoleBinding only: ClusterRoles outside the whitelist the objects may reference
	// (e.g. system:auth-delegator); the component gets bind on them.
	bind: [...string]
}

#ClusterRole:         #Allow & {apiGroup: "rbac.authorization.k8s.io", kind: "ClusterRole", resource: "clusterroles"}
#ClusterRoleBinding:  #Allow & {apiGroup: "rbac.authorization.k8s.io", kind: "ClusterRoleBinding", resource: "clusterrolebindings"}
#CRD:                 #Allow & {apiGroup: "apiextensions.k8s.io", kind: "CustomResourceDefinition", resource: "customresourcedefinitions"}
#ValidatingWebhook:   #Allow & {apiGroup: "admissionregistration.k8s.io", kind: "ValidatingWebhookConfiguration", resource: "validatingwebhookconfigurations"}
#MutatingWebhook:     #Allow & {apiGroup: "admissionregistration.k8s.io", kind: "MutatingWebhookConfiguration", resource: "mutatingwebhookconfigurations"}
#StorageClass:        #Allow & {apiGroup: "storage.k8s.io", kind: "StorageClass", resource: "storageclasses"}
#PriorityClass:       #Allow & {apiGroup: "scheduling.k8s.io", kind: "PriorityClass", resource: "priorityclasses"}
#APIService:          #Allow & {apiGroup: "apiregistration.k8s.io", kind: "APIService", resource: "apiservices"}
#CSIDriver:           #Allow & {apiGroup: "storage.k8s.io", kind: "CSIDriver", resource: "csidrivers"}
#Namespace:           #Allow & {apiGroup: "", kind: "Namespace", resource: "namespaces"}
#GatewayClass:        #Allow & {apiGroup: "gateway.networking.k8s.io", kind: "GatewayClass", resource: "gatewayclasses"}
#ClusterIssuer:       #Allow & {apiGroup: "cert-manager.io", kind: "ClusterIssuer", resource: "clusterissuers"}
#CCNP:                #Allow & {apiGroup: "cilium.io", kind: "CiliumClusterwideNetworkPolicy", resource: "ciliumclusterwidenetworkpolicies"}
#ClusterImageCatalog: #Allow & {apiGroup: "postgresql.cnpg.io", kind: "ClusterImageCatalog", resource: "clusterimagecatalogs"}

// Cilium network policy building blocks for a component's own policy.
Net: {
	// kube-apiserver (webhooks call in, controllers call out). `host` and `remote-node` cover
	// the control plane running on the node network.
	apiserverIn:  {fromEntities: ["kube-apiserver", "host", "remote-node"]}
	apiserverOut: {toEntities: ["kube-apiserver"]}
	// Same namespace.
	sameNamespaceIn:  {fromEndpoints: [{}]}
	sameNamespaceOut: {toEndpoints: [{}]}
	// Prometheus-style scrapers are not part of the platform yet: nothing allows metrics in.
	world: {toEntities: ["world"]}
	// DNS to kube-dns; part of every default-deny policy.
	dns: {
		toEndpoints: [{
			matchLabels: {
				"k8s:io.kubernetes.pod.namespace": "kube-system"
				"k8s:k8s-app":                     "kube-dns"
			}
		}]
		toPorts: [{
			ports: [{port: "53", protocol: "UDP"}, {port: "53", protocol: "TCP"}]
		}]
	}
	https: {toPorts: [{ports: [{port: "443", protocol: "TCP"}]}]}
}

#PSA: "restricted" | "baseline" | "privileged"

#Component: {
	name!: =~"^[a-z][a-z0-9-]{1,40}$"
	// Home namespace (target namespace of the Kustomization). None for components that only
	// own cluster-scoped objects or several namespaces.
	namespace?: string
	// The set (one signed artifact per set and cluster) the component is released in.
	set: *"system" | string

	// Short description for humans (CLAUDE/README listings, comments in the render).
	description?: string

	// Platform namespaces are `<name>-system` unless a component says otherwise.
	// The `rbac` set creates the namespace (labels, Pod Security) before the component's
	// Flux ServiceAccount exists, so a component cannot loosen its own namespace.
	createNamespace: *true | bool
	// More namespaces the chart writes to besides namespace.
	extraNamespaces: [...string]
	psa: {
		level: *"restricted" | #PSA
		// Required when the level is not `restricted`.
		reason?: string
		if level != "restricted" {
			reason!: string
		}
	}

	// Runs its Flux Kustomization as `flux-privileged` (cluster-admin) instead of the
	// component's own ServiceAccount.
	privileged: *false | bool
	if privileged {
		reason!: string
	}
	reason?: string

	// render: `helm template` in CI, the artifact holds plain objects (variant B).
	// helmrelease: the artifact holds a HelmRelease (variant A), allowed as a listed exception.
	// The HelmRelease lives in flux-system next to the ServiceAccounts, so helm-controller can
	// impersonate one without cross-namespace references; only privileged components may use it
	// for now (a component ServiceAccount has no rights in flux-system).
	variant: *"render" | "helmrelease"
	if variant == "helmrelease" {
		variantReason!: string
		privileged:     true
	}
	variantReason?: string

	chart?: #Chart
	// Helm values for the chart (exported as JSON for `helm template -f`).
	values: {...}
	// Kustomize patches applied to the rendered chart and the plain manifests together.
	postRender: [...{...}]
	// Plain objects shipped with (or instead of) the chart.
	manifests: #Manifests

	// Other components (by name, any set) that must be ready first.
	dependsOn: [...string]

	// Cluster-scoped objects the component may create. Empty: none.
	whitelist: [...#Allow]

	// Set `targetNamespace` on the Kustomization: every namespaced object lands in `namespace`.
	// Off for charts that deliberately write to several namespaces.
	targetNamespace: *true | bool

	// The component's CiliumNetworkPolicy and a default-deny policy are generated into `namespace`.
	// `policy: false` for namespaces that are not the component's own (kube-system) or whose
	// policies something else manages (flux-system).
	network: {
		policy:  *true | bool
		ingress: [...{...}]
		egress:  [...{...}]
	}

	// RBAC of the component's Flux ServiceAccount beyond the generated defaults (a Role with
	// all verbs on all namespaced resources in its namespace and extraNamespaces, a ClusterRole
	// from the whitelist). For components that create their own namespaces (teams): rules
	// bound cluster-wide, and the namespaces the ServiceAccount may write to (enforced by
	// admission, since RBAC can not bind a rule to namespaces that do not exist yet).
	rbac: {
		clusterWide:       [...{...}]
		allowedNamespaces: [...string]
		// Replaces the default Role of a namespace (least privilege where a wildcard is too much).
		namespaced: [string]: [...{...}]
	}

	// Images, besides the teams' own (ghcr.io/homelab-selfuryon/...@sha256), that pods in tenant
	// namespaces may run because this component starts them there (an operator's workload images).
	// Exact references, pinned by digest; the policy tenant-images-by-digest allows these and no others.
	tenantImages: [...=~"@sha256:[0-9a-f]{64}$"]

	// Kubernetes API groups/versions (`group/version`) the chart may test with Capabilities.
	apiVersions: [...string]
}

#Components: [string]~(ID,_): #Component & {name: *ID | string}

// Version of a component: a chart or release version and, for OCI charts, the digest.
#Ref: {
	version!: string
	digest?:  =~"^sha256:[0-9a-f]{64}$"
}

// "1.2.3" or "1.2.3@sha256:<hex>" (the form in latest.json and pins.json).
#ParseRef: {
	#in: string
	let _p = strings.Split(#in, "@")
	out: #Ref & {
		version: _p[0]
		if len(_p) > 1 {
			digest: _p[1]
		}
	}
}

#ValidatingAdmissionPolicy:        #Allow & {apiGroup: "admissionregistration.k8s.io", kind: "ValidatingAdmissionPolicy", resource: "validatingadmissionpolicies"}
#ValidatingAdmissionPolicyBinding: #Allow & {apiGroup: "admissionregistration.k8s.io", kind: "ValidatingAdmissionPolicyBinding", resource: "validatingadmissionpolicybindings"}

// A SecretProviderClass for the OpenBao provider that syncs one key into a Kubernetes Secret
// (platform components that insist on a Secret, listed exception; admission allows `secretObjects`
// in `*-system` namespaces only). The pod that mounts the volume triggers the sync.
//
// OpenBao side (platform-terraform/openbao): role `platform-<cluster>-<component>`, bound to the
// ServiceAccount of the mounting pod, policy read on kv/data/platform/<cluster>/<component>.
#OpenBaoSecret: {
	#clusterName: string
	#component:   string
	#key:         string
	#secret:      string
	out: {
		apiVersion: "secrets-store.csi.x-k8s.io/v1"
		kind:       "SecretProviderClass"
		spec: {
			provider: "openbao"
			parameters: {
				roleName:      "platform-\(#clusterName)-\(#component)"
				baoAddress:    "https://openbao.openbao-system.svc:8200"
				baoCACertPath: "/openbao/tls/ca.crt"
				objects: """
					- objectName: \(#key)
					  secretPath: kv/data/platform/\(#clusterName)/\(#component)
					  secretKey: \(#key)
					"""
			}
			secretObjects: [{
				secretName: #secret
				type:       "Opaque"
				data:       [{objectName: #key, key: #key}]
			}]
		}
	}
}
