package policies

import (
	"encoding/json"
	"list"
	"regexp"
	"strings"

	"github.com/homelab-selfuryon/platform-components/schema"
	"github.com/homelab-selfuryon/platform-components/teams"
	core_v1 "cue.dev/x/k8s.io/api/core/v1"
	cilium_v2 "github.com/homelab-selfuryon/platform-components/crd/cilium/v2"
)

// Kyverno CEL policies (policies.kyverno.io/v1), all Enforce unless a rule says Audit. Lives in the
// `policy` set: the CRDs come with Kyverno in `system`.
//
//   Workloads (every namespace)
//     disallow-latest-tag, restrict-image-registries, disallow-default-namespace,
//     restrict-service-exposure, require-requests-limits (Audit), cleanup-finished-pods
//   Tenant namespaces (label homelab-selfuryon.github.io/team)
//     tenant-images-by-digest        images ghcr.io/homelab-selfuryon/*@sha256 only
//     tenant-image-signatures-*      cosign keyless identity per environment (ImageValidatingPolicy):
//                                    staging/prod: app-release.yaml, preview: app-preview.yaml
//     tenant-deny-shell-access       no exec, attach, port-forward, ephemeral containers
//     tenant-deny-sa-token-secrets   no legacy ServiceAccount token Secrets
//     tenant-deny-cluster-scoped     no webhooks, CRDs, ClusterRoles, CiliumClusterwideNetworkPolicies
//                                    from ServiceAccounts of tenant namespaces
//     tenant-namespace-labels        Pod Security restricted, name matches team and environment
//     tenant-default-deny / tenant-default-limits   generated per tenant namespace
//     preview-quota-<team>           generated per preview namespace
//     preview-deployer-scope         the preview deploy ServiceAccount acts in <team>-pr-<n> only
//   Platform
//     component-whitelist            names of the cluster-scoped objects a component ServiceAccount creates
//     component-namespaces           namespaces a component ServiceAccount (teams) writes to
//     kustomization-service-accounts which ServiceAccount a Flux Kustomization may use
//     helmrelease-service-accounts   HelmReleases: listed components only, own ServiceAccount and namespace
//     secretobjects-only-in-system   SecretProviderClass `secretObjects` in `*-system` namespaces only

let _team = "\(schema.#Prefix)/team"
let _env = "\(schema.#Prefix)/env"
let _expose = "\(schema.#Prefix)/expose"

// A shell glob (`*`) as an anchored RE2 regular expression.
#GlobRegex: {
	#g:  string
	out: "^" + strings.Join([for p in strings.Split(#g, "*") {regexp.QuoteMeta(p)}], ".*") + "$"
}

// Namespaces of the teams.
_tenantNS: matchExpressions: [{key: _team, operator: "Exists"}]

// Pods (CREATE/UPDATE), with every container of the pod in variables.containers.
_pods: {
	evaluation: background: enabled: true
	matchConstraints: resourceRules: [{
		apiGroups:   [""]
		apiVersions: ["v1"]
		operations:  ["CREATE", "UPDATE"]
		resources:   ["pods"]
	}]
	variables: [{
		name:       "containers"
		expression: "object.spec.containers + object.spec.?initContainers.orValue([]) + object.spec.?ephemeralContainers.orValue([])"
	}, ...]
}

// A GeneratingPolicy that creates #object in every Namespace matching #condition (CEL over the
// Namespace). #object is typed CUE without a namespace (generator.Apply sets it); it reaches CEL as
// JSON through json.unmarshal.
#Generate: {
	#condition!: string
	#object!: {
		apiVersion!: string
		kind!:       string
		metadata!: name!: string
		...
	}

	let _json = json.Marshal(#object)

	// The JSON is embedded in a single-quoted CEL string.
	_quoted: _json & !~"'"

	spec: {
		evaluation: {
			synchronize: enabled:      true
			generateExisting: enabled: true
		}
		matchConstraints: resourceRules: [{
			apiGroups:   [""]
			apiVersions: ["v1"]
			operations:  ["CREATE", "UPDATE"]
			resources:   ["namespaces"]
		}]
		matchConditions: [{name: "namespace", expression: #condition}]
		generate:        [{expression: "generator.Apply(object.metadata.name, [json.unmarshal('\(_quoted)')])"}]
	}
}

// Type-checks a CiliumNetworkPolicy spec against the schema (`spec` is optional in the schema, so
// it can not be selected from the definition directly).
_cnpSpec: {
	#spec: _
	out: (cilium_v2.#CiliumNetworkPolicy & {
		metadata: {name: "typecheck", namespace: "typecheck"}
		spec:     #spec
	}).spec
}

#Policies: {
	#cluster: schema.#Cluster

	// Every other component of the cluster except `rbac` (built from this one) and this one.
	#components: schema.#Components
	#teams: [string]: teams.#Team

	let _all = #components
	let _sets = #cluster.sets
	let _registries = json.Marshal(#cluster.security.allowedRegistries)
	let _wf = #cluster.artifacts.workflows
	let _issuer = #cluster.artifacts.issuer
	let _image = "\(#cluster.artifacts.registry)/"

	// username -> what the component's ServiceAccount may create at cluster scope
	let _whitelists = {
		for _, c in _all if !c.privileged && len(c.whitelist) > 0 {
			"system:serviceaccount:flux-system:component-\(c.name)": [for w in c.whitelist {
				g: w.apiGroup
				k: w.kind
				n: [for n in w.names {(#GlobRegex & {#g: n}).out}]
			}]
		}
	}

	// Heterogeneous values: handed to CEL as JSON (raw string, the regexes carry backslashes).
	let _whitelistsJSON = json.Marshal(_whitelists) & !~"'"

	// apiGroup -> resources the whitelists mention
	let _wlResources = {
		for _, c in _all if !c.privileged for w in c.whitelist {
			(w.apiGroup): (w.resource): true
		}
	}

	// username -> namespaces (regexes) a component may write to, for components that create their own
	let _nsRules = {
		for _, c in _all if !c.privileged && len(c.rbac.allowedNamespaces) > 0 {
			"system:serviceaccount:flux-system:component-\(c.name)": [for n in c.rbac.allowedNamespaces {(#GlobRegex & {#g: n}).out}]
		}
	}
	let _nsGroupSet = {
		for _, c in _all if !c.privileged && len(c.rbac.allowedNamespaces) > 0
		for r in list.Concat([c.rbac.clusterWide, [for _, rs in c.rbac.namespaced for r in rs {r}]])
		for g in r.apiGroups {(g): true}
	}
	let _nsGroups = list.SortStrings([for g, _ in _nsGroupSet {g}])

	// Kustomization name -> ServiceAccount
	let _kustomizations = {
		gitops:      "gitops-root"
		"argo-apps": "argo-apps"
		// Bootstrap-time sibling: the rbac set itself runs privileged.
		rbac: "flux-privileged"
		for s in _sets {"set-\(s)": "gitops-root"}
		for _, c in _all {
			(c.name): [if c.privileged {"flux-privileged"}, "component-\(c.name)"][0]
		}
	}
	let _privileged = list.Concat([["rbac"], [for _, c in _all if c.privileged {c.name}]])

	// HelmRelease name -> ServiceAccount and namespace, for the variant A components
	let _helmReleases = {
		for _, c in _all if c.variant == "helmrelease" {
			(c.name): {
				sa: [if c.privileged {"flux-privileged"}, "component-\(c.name)"][0]
				ns: c.namespace
			}
		}
	}

	component: schema.#Component & {
		name:        "kyverno-policies"
		description: "Kyverno CEL policies: workloads, tenants, component ServiceAccounts."
		set:         "policy"
		dependsOn:   ["kyverno"]

		manifests: global: validatingPolicy: {
			// ---- Workloads ------------------------------------------------------------------
			"disallow-latest-tag": spec: _pods & {
				validationActions: ["Deny"]
				validations: [{
					expression: "variables.containers.all(c, c.image.matches('^.+(:[^:/@]+(@sha256:[0-9a-f]{64})?|@sha256:[0-9a-f]{64})$') && !c.image.matches(':latest(@|$)'))"
					message:    "Images must be pinned to a tag other than latest, or to a digest."
				}]
			}

			"restrict-image-registries": spec: _pods & {
				validationActions: ["Deny"]
				variables:         [_, {name: "registries", expression: _registries}]
				validations: [{
					expression:        "variables.containers.all(c, variables.registries.exists(r, c.image.startsWith(r)))"
					messageExpression: "'Images must come from one of ' + variables.registries.join(', ') + ' and name the registry explicitly.'"
					message:           "Images must come from an allowed registry."
				}]
			}

			"disallow-default-namespace": spec: {
				validationActions: ["Deny"]
				evaluation: background: enabled: true
				// One rule per API group: a rule is the cross product of its groups and resources.
				// CREATE only: the apiserver keeps updating its own objects there.
				matchConstraints: resourceRules: [
					for g, r in {
						"":    ["pods"]
						apps:  ["deployments", "statefulsets", "daemonsets"]
						batch: ["jobs", "cronjobs"]
					} {
						apiGroups:   [g]
						apiVersions: ["v1"]
						operations:  ["CREATE"]
						resources:   r
					},
				]
				validations: [{
					expression: "object.metadata.?namespace.orValue('') != 'default'"
					message:    "Workloads must not run in the default namespace."
				}]
			}

			"restrict-service-exposure": spec: {
				validationActions: ["Deny"]
				evaluation: background: enabled: true
				matchConstraints: resourceRules: [{
					apiGroups:   [""]
					apiVersions: ["v1"]
					operations:  ["CREATE", "UPDATE"]
					resources:   ["services"]
				}]
				validations: [{
					expression: """
						!(object.spec.?type.orValue('ClusterIP') in ['LoadBalancer', 'NodePort'])
						|| object.metadata.?namespace.orValue('').endsWith('-system')
						|| namespaceObject.?metadata.?labels.orValue({}).exists(k, k == '\(_expose)' && namespaceObject.metadata.labels[k] == 'true')
						"""
					message: "LoadBalancer/NodePort Services expose the node's addresses: label the namespace \(_expose)=true to allow them."
				}]
			}

			"require-requests-limits": spec: _pods & {
				validationActions: ["Audit"]
				matchConstraints: namespaceSelector: _tenantNS
				validations: [{
					expression: """
						variables.containers.all(c,
						  c.?resources.?requests.?cpu.hasValue() &&
						  c.?resources.?requests.?memory.hasValue() &&
						  c.?resources.?limits.?memory.hasValue())
						"""
					message: "Containers should set cpu and memory requests and a memory limit."
				}]
			}

			// ---- Tenant namespaces -----------------------------------------------------------
			"tenant-images-by-digest": spec: _pods & {
				validationActions: ["Deny"]
				matchConstraints: namespaceSelector: _tenantNS
				validations: [{
					expression: "variables.containers.all(c, c.image.startsWith('\(_image)') && c.image.matches('@sha256:[0-9a-f]{64}$'))"
					message:    "Tenant images must come from \(_image) and be pinned by digest (@sha256:...)."
				}]
			}

			"tenant-deny-shell-access": spec: {
				validationActions: ["Deny"]
				// Break-glass (system:masters) is audited, not blocked.
				matchConditions: [{name: "not-break-glass", expression: "!('system:masters' in request.userInfo.groups)"}]
				matchConstraints: {
					namespaceSelector: _tenantNS
					resourceRules: [{
						apiGroups:   [""]
						apiVersions: ["v1"]
						operations:  ["CONNECT"]
						resources:   ["pods/exec", "pods/attach", "pods/portforward"]
					}, {
						apiGroups:   [""]
						apiVersions: ["v1"]
						operations:  ["CREATE", "UPDATE"]
						resources:   ["pods/ephemeralcontainers"]
					}]
				}
				validations: [{
					expression: "false"
					message:    "No exec, attach, port-forward or ephemeral containers in tenant namespaces."
				}]
			}

			"tenant-deny-sa-token-secrets": spec: {
				validationActions: ["Deny"]
				evaluation: background: enabled: true
				matchConstraints: {
					namespaceSelector: _tenantNS
					resourceRules: [{
						apiGroups:   [""]
						apiVersions: ["v1"]
						operations:  ["CREATE", "UPDATE"]
						resources:   ["secrets"]
					}]
				}
				validations: [{
					expression: "object.?type.orValue('Opaque') != 'kubernetes.io/service-account-token'"
					message:    "Long-lived ServiceAccount token Secrets are not allowed: use projected, audience-bound tokens."
				}]
			}

			// Webhooks, CRDs, ClusterRoles and cluster-wide network policies are the platform's.
			"tenant-deny-cluster-scoped": spec: {
				validationActions: ["Deny"]
				matchConditions: [{
					name:       "tenant-serviceaccount"
					expression: "request.userInfo.username.matches('^system:serviceaccount:[a-z0-9]+-(staging|prod|pr-[0-9]+):')"
				}]
				matchConstraints: resourceRules: [
					{
						apiGroups:   ["admissionregistration.k8s.io"]
						apiVersions: ["*"]
						operations:  ["CREATE", "UPDATE"]
						resources:   ["validatingwebhookconfigurations", "mutatingwebhookconfigurations", "validatingadmissionpolicies", "validatingadmissionpolicybindings"]
					},
					{
						apiGroups:   ["apiextensions.k8s.io"]
						apiVersions: ["*"]
						operations:  ["CREATE", "UPDATE"]
						resources:   ["customresourcedefinitions"]
					},
					{
						apiGroups:   ["rbac.authorization.k8s.io"]
						apiVersions: ["*"]
						operations:  ["CREATE", "UPDATE"]
						resources:   ["clusterroles", "clusterrolebindings"]
					},
					{
						apiGroups:   ["cilium.io"]
						apiVersions: ["*"]
						operations:  ["CREATE", "UPDATE"]
						resources:   ["ciliumclusterwidenetworkpolicies"]
					},
				]
				validations: [{
					expression: "false"
					message:    "Webhooks, CRDs, ClusterRoles and CiliumClusterwideNetworkPolicies can not be created from tenant namespaces."
				}]
			}

			// Namespaces carrying a team label are tenant namespaces: Pod Security restricted, and the
			// name must say which team and environment they are (admission selects on these labels).
			"tenant-namespace-labels": spec: {
				validationActions: ["Deny"]
				evaluation: background: enabled: true
				matchConstraints: resourceRules: [{
					apiGroups:   [""]
					apiVersions: ["v1"]
					operations:  ["CREATE", "UPDATE"]
					resources:   ["namespaces"]
				}]
				variables: [
					{name: "labels", expression: "object.metadata.?labels.orValue({})"},
					{name: "team", expression: "variables.labels[?'\(_team)'].orValue('')"},
					{name: "env", expression: "variables.labels[?'\(_env)'].orValue('')"},
				]
				validations: [
					{
						expression: "variables.team == '' || variables.labels[?'pod-security.kubernetes.io/enforce'].orValue('') == 'restricted'"
						message:    "Tenant namespaces must enforce Pod Security `restricted`."
					},
					{
						expression: "variables.team == '' || (variables.env in ['staging', 'prod'] && object.metadata.name == variables.team + '-' + variables.env) || (variables.env == 'preview' && object.metadata.name.matches('^' + variables.team + '-pr-[0-9]+$'))"
						message:    "Namespace name must be <team>-<env> (staging, prod) or <team>-pr-<n> (env preview) for its team and env labels."
					},
					{
						expression: "!object.metadata.name.matches('^[a-z0-9]+-pr-[0-9]+$') || (variables.team != '' && variables.env == 'preview')"
						message:    "Preview namespaces (<team>-pr-<n>) need the team label and env=preview."
					},
				]
			}

			// ---- Platform ----------------------------------------------------------------------
			// Names of what a component's ServiceAccount creates at cluster scope; kinds are
			// limited by its ClusterRole, names can not be in RBAC.
			"component-whitelist": spec: {
				validationActions: ["Deny"]
				matchConditions: [{
					name:       "component-serviceaccount"
					expression: "request.userInfo.username.startsWith('system:serviceaccount:flux-system:component-')"
				}]
				matchConstraints: resourceRules: [
					for g, rs in _wlResources {
						apiGroups:   [g]
						apiVersions: ["*"]
						operations:  ["CREATE", "UPDATE"]
						resources:   list.SortStrings([for r, _ in rs {r}])
						scope:       "Cluster"
					},
				]
				variables: [
					{name: "allowed", expression: "json.unmarshal(r'\(_whitelistsJSON)')"},
					{name: "user", expression: "request.userInfo.username"},
					{name: "group", expression: "object.apiVersion.contains('/') ? object.apiVersion.split('/')[0] : ''"},
				]
				validations: [{
					expression:        "variables.user in variables.allowed && variables.allowed[variables.user].exists(r, r.g == variables.group && r.k == object.kind && r.n.exists(p, object.metadata.name.matches(p)))"
					messageExpression: "'The component ServiceAccount may not create ' + object.kind + ' ' + object.metadata.name + ' (not in the component whitelist).'"
					message:           "Not in the component whitelist."
				}]
			}

			"component-namespaces": spec: {
				validationActions: ["Deny"]
				matchConditions: [{
					name:       "component-with-namespaces"
					expression: "request.userInfo.username in \(json.Marshal([for u, _ in _nsRules {u}]))"
				}]
				matchConstraints: resourceRules: [{
					apiGroups:   _nsGroups
					apiVersions: ["*"]
					operations:  ["CREATE", "UPDATE", "DELETE"]
					resources:   ["*"]
					scope:       "Namespaced"
				}]
				variables: [
					{name: "allowed", expression: json.Marshal(_nsRules)},
					{name: "target", expression: "request.operation == 'DELETE' ? oldObject : object"},
				]
				validations: [{
					expression: "variables.allowed[request.userInfo.username].exists(p, variables.target.metadata.namespace.matches(p))"
					message:    "The component ServiceAccount may not write to this namespace."
				}]
			}

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
					{name: "expected", expression: json.Marshal(_kustomizations)},
					{name: "privileged", expression: json.Marshal(_privileged)},
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
					{name: "expected", expression: json.Marshal(_helmReleases)},
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

			"secretobjects-only-in-system": spec: {
				validationActions: ["Deny"]
				evaluation: background: enabled: true
				matchConstraints: resourceRules: [{
					apiGroups:   ["secrets-store.csi.x-k8s.io"]
					apiVersions: ["*"]
					operations:  ["CREATE", "UPDATE"]
					resources:   ["secretproviderclasses"]
				}]
				validations: [{
					expression: "size(object.spec.?secretObjects.orValue([])) == 0 || object.metadata.namespace.endsWith('-system')"
					message:    "Syncing secrets into Kubernetes Secrets (secretObjects) is for platform components in *-system namespaces: apps read secrets as files."
				}]
			}

			// The preview deploy ServiceAccount of each team acts in <team>-pr-<n> namespaces only.
			if len(#teams) > 0 {
				"preview-deployer-scope": spec: {
					validationActions: ["Deny"]
					matchConditions: [{
						name:       "preview-deployer"
						expression: "request.userInfo.username in \(json.Marshal([for _, t in #teams {"system:serviceaccount:argocd:\(t.previewDeployer)"}]))"
					}]
					matchConstraints: resourceRules: [{
						apiGroups:   list.SortStrings([for g, _ in {for k in teams.#DeployKinds {(k.group): true}} {g}])
						apiVersions: ["*"]
						operations:  ["CREATE", "UPDATE", "DELETE"]
						resources:   ["*"]
					}]
					variables: [
						{name: "allowed", expression: json.Marshal({for _, t in #teams {"system:serviceaccount:argocd:\(t.previewDeployer)": t.namespaces.previewRegex}})},
						{name: "target", expression: "request.operation == 'DELETE' ? oldObject : object"},
						{name: "ns", expression: "variables.target.kind == 'Namespace' ? variables.target.metadata.name : variables.target.metadata.?namespace.orValue('')"},
					]
					validations: [{
						expression: "variables.ns.matches(variables.allowed[request.userInfo.username])"
						message:    "The preview deploy ServiceAccount may only act in its team's preview namespaces (<team>-pr-<n>)."
					}]
				}
			}
		}

		// Cosign keyless identity of the workflow that built an image, per environment. The
		// environment is the label of the namespace, which only the platform sets.
		manifests: global: imageValidatingPolicy: {
			"tenant-image-signatures-release": spec: _ivp & {
				matchConstraints: namespaceSelector: matchExpressions: [{key: _env, operator: "In", values: ["staging", "prod"]}]
				attestors: [{
					name: "release"
					cosign: keyless: identities: [{issuer: _issuer, subjectRegExp: _wf.appRelease}]
				}]
				validations: [{
					expression: "images.containers.map(image, verifyImageSignatures(image, [attestors.release])).all(e, e > 0)"
					message:    "Images in staging and prod must be signed by app-release.yaml of github-workflows."
				}]
			}
			"tenant-image-signatures-preview": spec: _ivp & {
				matchConstraints: namespaceSelector: matchExpressions: [{key: _env, operator: "In", values: ["preview"]}]
				attestors: [{
					name: "preview"
					cosign: keyless: identities: [{issuer: _issuer, subjectRegExp: _wf.appPreview}]
				}]
				validations: [{
					expression: "images.containers.map(image, verifyImageSignatures(image, [attestors.preview])).all(e, e > 0)"
					message:    "Images in preview namespaces must be signed by app-preview.yaml of github-workflows."
				}]
			}
		}

		// Defaults for every tenant namespace, existing and future: nothing in, egress only DNS; and
		// requests/limits for containers that declare none. Applications open what they need with
		// their own CiliumNetworkPolicy (platform-kit renders it). Platform namespaces get theirs
		// from the component render.
		manifests: global: generatingPolicy: {
			"tenant-default-deny": spec: (#Generate & {
				#condition: "has(object.metadata.labels) && '\(_team)' in object.metadata.labels"
				#object: {
					apiVersion: "cilium.io/v2"
					kind:       "CiliumNetworkPolicy"
					metadata: name: "default-deny"
					spec: (_cnpSpec & {
						#spec: {
							description:      "Default deny (tenant-default-deny): no ingress, egress only DNS. Allow traffic with policies next to the workload."
							endpointSelector: {}
							ingress:          [{}]
							egress:           [schema.Net.dns]
						}
					}).out
				}
			}).spec

			"tenant-default-limits": spec: (#Generate & {
				#condition: "has(object.metadata.labels) && '\(_team)' in object.metadata.labels"
				#object: {
					apiVersion: "v1"
					kind:       "LimitRange"
					metadata: name: "default-limits"
					spec: core_v1.#LimitRangeSpec & {
						limits: [{
							type:           "Container"
							defaultRequest: {cpu: "10m", memory: "32Mi"}
							default: memory: "256Mi"
						}]
					}
				}
			}).spec

			for _, t in #teams {
				"preview-quota-\(t.name)": spec: (#Generate & {
					#condition: "has(object.metadata.labels) && object.metadata.labels[?'\(_team)'].orValue('') == '\(t.name)' && object.metadata.labels[?'\(_env)'].orValue('') == 'preview'"
					#object: {
						apiVersion: "v1"
						kind:       "ResourceQuota"
						metadata: name: "team-quota"
						spec: core_v1.#ResourceQuotaSpec & {
							hard: {
								"requests.cpu":         t.quota.preview.requestsCPU
								"requests.memory":      t.quota.preview.requestsMemory
								"limits.memory":        t.quota.preview.limitsMemory
								pods:                   t.quota.preview.pods
								persistentvolumeclaims: t.quota.preview.persistentVolumeClaims
								"requests.storage":     t.quota.preview.requestsStorage
							}
						}
					}
				}).spec
			}
		}

		// Finished pods that no Job owns (Jobs clean up after themselves).
		manifests: global: deletingPolicy: "cleanup-finished-pods": spec: {
			schedule: "0 * * * *"
			matchConstraints: resourceRules: [{
				apiGroups:   [""]
				apiVersions: ["v1"]
				operations:  ["*"]
				resources:   ["pods"]
				scope:       "Namespaced"
			}]
			conditions: [{
				name:       "finished"
				expression: "object.?status.?phase.orValue('') in ['Succeeded', 'Failed']"
			}, {
				name:       "not-from-a-job"
				expression: "!object.metadata.?ownerReferences.orValue([]).exists(o, o.kind == 'Job')"
			}]
		}

		// The Kyverno controllers create what the generating policies describe.
		manifests: global: clusterRole: "kyverno:generate-tenant-defaults": {
			metadata: labels: {
				"rbac.kyverno.io/aggregate-to-background-controller": "true"
				"rbac.kyverno.io/aggregate-to-admission-controller":  "true"
			}
			rules: [{
				apiGroups: ["cilium.io"]
				resources: ["ciliumnetworkpolicies"]
				verbs:     ["create", "update", "patch", "delete", "get", "list", "watch"]
			}, {
				apiGroups: [""]
				resources: ["limitranges", "resourcequotas"]
				verbs:     ["create", "update", "patch", "delete", "get", "list", "watch"]
			}]
		}
		manifests: global: clusterRole: "kyverno:cleanup-pods": {
			metadata: labels: "rbac.kyverno.io/aggregate-to-cleanup-controller": "true"
			rules: [{
				apiGroups: [""]
				resources: ["pods"]
				verbs:     ["get", "list", "watch", "delete"]
			}]
		}

		whitelist: [
			schema.#ClusterRole & {names: ["kyverno:generate-tenant-defaults", "kyverno:cleanup-pods"]},
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
					names:    list.SortStrings([for n, _ in component.manifests.global[key] {n}])
				}
			},
		]
	}
}

// Shared by the image verification policies: pods (and through autogen their controllers) with the
// images of the platform's registry.
_ivp: {
	validationActions: ["Deny"]
	evaluation: background: enabled: false
	matchConstraints: resourceRules: [{
		apiGroups:   [""]
		apiVersions: ["v1"]
		operations:  ["CREATE", "UPDATE"]
		resources:   ["pods"]
	}]
	matchImageReferences: [{glob: "ghcr.io/homelab-selfuryon/*"}]
	...
}
