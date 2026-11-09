package render

import (
	"encoding/json"
	"encoding/yaml"
	"list"
	"strings"

	flux_kustomize_v1 "cue.dev/x/crd/fluxcd.io/kustomize/v1"
	"github.com/homelab-selfuryon/platform-components/schema"
)

// Namespace of every Flux object of the platform.
#FluxNS: "flux-system"

// Flattens a #Manifests value into its objects, each already marshalled to YAML; join them with
// "---\n" for a stream.
//
// Marshalling each object, rather than collecting the objects into a list for
// yaml.MarshalStream, avoids a full copy of every manifest: the body of a list comprehension is
// a struct literal and CUE never structure-shares one, so `[for o in objects {o}]` evaluates each
// object a second time. Only the key order within maps differs from MarshalStream (the render
// script normalizes it anyway).
#Objects: {
	#m: _
	out: list.Concat([[
		for objects in #m.global
		for object in objects {yaml.Marshal(object)},
	], [
		for scope in #m.scoped
		for objects in scope
		for object in objects {yaml.Marshal(object)},
	]])
}

// The component's objects plus what the platform generates for every component namespace:
// a default-deny CiliumNetworkPolicy (nothing in, egress only DNS) and the component's own policy.
#Complete: {
	#c: schema.#Component

	out: schema.#Manifests & #c.manifests

	if #c.namespace != _|_ if #c.network.policy {
		let _ns = #c.namespace
		out: scoped: (_ns): ciliumNetworkPolicy: {
			"default-deny": spec: {
				description:      "Default deny: no ingress, egress only DNS (generated for platform namespaces)."
				endpointSelector: {}
				ingress:          [{}]
				egress:           [schema.Net.dns]
			}
			(#c.name): spec: {
				description:      "Network policy of the \(#c.name) component."
				endpointSelector: {}
				if len(#c.network.ingress) > 0 {
					ingress: #c.network.ingress
				}
				if len(#c.network.egress) > 0 {
					egress: #c.network.egress
				}
			}
		}
	}
}

// The Flux Kustomization that applies a component's directory of the set artifact.
#Kustomization: {
	#c: schema.#Component

	let _sa = [
		if #c.privileged {"flux-privileged"},
		"component-\(#c.name)",
	][0]

	out: flux_kustomize_v1.#Kustomization & {
		metadata: {
			name:      #c.name
			namespace: #FluxNS
			labels: {
				"\(schema.#Prefix)/managed-by": "platform"
				"\(schema.#Prefix)/component":  #c.name
				"\(schema.#Prefix)/set":        #c.set
			}
		}
		spec: {
			interval:      "1h"
			retryInterval: "2m"
			timeout:       "10m"
			path:          "./components/\(#c.name)"
			prune:         true
			wait:          true
			sourceRef: {
				kind: "OCIRepository"
				name: "set-\(#c.set)"
			}
			serviceAccountName: _sa
			if #c.namespace != _|_ if #c.targetNamespace if #c.variant == "render" {
				targetNamespace: #c.namespace
			}
			if len(#c.dependsOn) > 0 {
				dependsOn: [for d in #c.dependsOn {name: d}]
			}
		}
	}
}

// Variant A: the chart is installed by helm-controller, hooks included. The source and the
// HelmRelease live in flux-system next to the ServiceAccount the install runs as (multi-tenant
// lockdown forbids cross-namespace references); the release, its storage and every object land
// in the component's namespace. Admission: `helmrelease-service-accounts`.
#HelmRelease: {
	#c: schema.#Component

	let _chart = #c.chart
	let _name = #c.name
	let _release = [if _chart.releaseName != _|_ {_chart.releaseName}, _name][0]

	out: schema.#Manifests & {
		scoped: (#FluxNS): {
			if _chart.kind == "helm" {
				helmRepository: (_name): spec: {
					url:      _chart.url
					interval: "12h"
				}
				helmRelease: (_name): spec: chart: spec: {
					chart:     _chart.name
					version:   _chart.version
					interval:  "12h"
					sourceRef: {kind: "HelmRepository", name: _name}
				}
			}
			if _chart.kind == "oci" {
				ociRepository: (_name): spec: {
					url:      "\(_chart.url)/\(_chart.name)"
					interval: "12h"
					if _chart.digest != _|_ {
						ref: digest: _chart.digest
					}
					if _chart.digest == _|_ {
						ref: tag: _chart.version
					}
					layerSelector: {
						mediaType: "application/vnd.cncf.helm.chart.content.v1.tar+gzip"
						operation: "copy"
					}
				}
				helmRelease: (_name): spec: chartRef: {kind: "OCIRepository", name: _name}
			}
			if _chart.kind == "git" {
				gitRepository: (_name): spec: {
					url: _chart.url
					ref: tag: _chart.version
					interval: "12h"
				}
				helmRelease: (_name): spec: chart: spec: {
					chart:             _chart.path
					interval:          "12h"
					reconcileStrategy: "Revision"
					sourceRef:         {kind: "GitRepository", name: _name}
				}
			}
			helmRelease: (_name): spec: {
				releaseName:        _release
				targetNamespace:    #c.namespace
				storageNamespace:   #c.namespace
				interval:           "1h"
				serviceAccountName: [if #c.privileged {"flux-privileged"}, "component-\(_name)"][0]
				// Changes made in the cluster by hand are reverted, as with a Kustomization.
				driftDetection: mode: "enabled"
				install: {
					crds: "CreateReplace"
					remediation: retries: 3
				}
				upgrade: {
					crds:        "CreateReplace"
					remediation: {retries: 3, strategy: "rollback"}
				}
				values: #c.values
				if len(#c.postRender) > 0 {
					postRenderers: [{kustomize: patches: #c.postRender}]
				}
			}
		}
	}
}

// What the render script needs to know about a component (written as meta.json).
#Meta: {
	#c:       schema.#Component
	#cluster: schema.#Cluster

	out: {
		name:    #c.name
		set:     #c.set
		variant: #c.variant
		if #c.namespace != _|_ {
			namespace: #c.namespace
		}
		targetNamespace:   #c.targetNamespace
		namespaces:        list.Concat([[if #c.namespace != _|_ {#c.namespace}], #c.extraNamespaces])
		privileged:        #c.privileged
		allowedNamespaces: list.Concat([[if #c.namespace != _|_ {#c.namespace}], #c.extraNamespaces, #c.rbac.allowedNamespaces, [for k, _ in #c.rbac.namespaced {k}]])
		bindable:          list.Concat([for w in #c.whitelist {w.bind}])
		whitelist:         #c.whitelist
		kubeVersion:       #cluster.kubernetes.version
		apiVersions:       list.Concat([#c.apiVersions, #cluster.kubernetes.apiVersions])
		hasPatches:        len(#c.postRender) > 0
		if #c.chart != _|_ {
			let _chart = #c.chart
			chart: {
				kind:        _chart.kind
				url:         _chart.url
				name:        _chart.name
				version:     _chart.version
				includeCRDs: _chart.includeCRDs
				release:     [if _chart.releaseName != _|_ {_chart.releaseName}, #c.name][0]
				if _chart.digest != _|_ {
					digest: _chart.digest
				}
				if _chart.path != _|_ {
					path: _chart.path
				}
			}
		}
	}
}

// Everything the render of one component produces.
#Rendered: {
	#c:       schema.#Component
	#cluster: schema.#Cluster

	// helmrelease components ship a HelmRelease and its source; the chart itself is still rendered
	// for diffs and checks (`preview`), but not published.
	let _c = #c
	let _cl = #cluster
	let _extra = [
		if _c.variant == "helmrelease" {(#HelmRelease & {#c: _c}).out},
		{},
	][0]
	let _complete = (#Complete & {#c: _c}).out
	let _published = schema.#Manifests & _complete & _extra

	meta:          (#Meta & {#c: _c, #cluster: _cl}).out
	kustomization: (#Kustomization & {#c: _c}).out
	// Plain objects as one YAML stream (the chart output is added by the script).
	plain: strings.Join((#Objects & {#m: _published}).out, "---\n")
}

// All components of a cluster, grouped into its sets.
#Cluster: {
	#cluster:    schema.#Cluster
	#components: schema.#Components

	let _cl = #cluster
	components: [string]: #Rendered
	for name, c in #components {
		components: (name): #Rendered & {#c: c, #cluster: _cl}
	}

	let _comps = components
	sets: {
		for s in #cluster.sets {
			(s): {
				names: [for n, r in _comps if r.meta.set == s {n}]
				// Sorted for a stable file; Flux orders by dependsOn anyway.
				kustomizations: strings.Join([
					for n in list.SortStrings(names) {yaml.Marshal(_comps[n].kustomization)},
				], "---\n")
			}
		}
	}
	// Every component is in a set the cluster has.
	_ok: {for n, r in components {(n): true & list.Contains(#cluster.sets, r.meta.set)}}
}

// meta.json as JSON text.
#MetaJSON: {
	#r:  #Rendered
	out: json.Marshal(#r.meta)
}
