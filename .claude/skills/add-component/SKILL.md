---
name: add-component
description: Add a platform component (chart or plain objects) to platform-components - component package, whitelist, namespace and network policy, version registry, cluster wiring, verification. Use whenever something new should run in a cluster.
---

# Adding a component

A component is one CUE package in `components/<category>/<name>/` and one directory
`components/<name>/` of its set's artifact. Delivery (see `meta/delivery.md`): a Flux
`Kustomization` named `<name>` applies it, as the ServiceAccount `component-<name>`
(`flux-privileged` only for listed core components).

## Decide first

| Question    | Answer                                                                                                                                                                                                                                                                                                                                                                                     |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Which set?  | `system` (CNI, Flux, Kyverno, CRDs, cert-manager, internal CA), `platform` (everything else that runs), `policy` (CRs of the operators in `system`/`platform`: policies, issuers, Gateways), `tenants` (teams). Sets are applied in that order; within a set `dependsOn` orders components. A CR may sit in the same set as its CRD only if the component `dependsOn` the CRD's component. |
| Variant?    | `render` (default): `helm template` in CI, the artifact holds plain objects. `helmrelease` only for a chart that cannot be rendered (needs `lookup`, install-time state): give `variantReason`; CI still renders it for the diff and the checks.                                                                                                                                           |
| Privileged? | Only if nothing below it can install it. `privileged: true` needs a `reason`. Every other component gets a ServiceAccount with exactly its whitelist.                                                                                                                                                                                                                                      |
| Namespace   | `<name>-system`, label `managed-by: platform`, Pod Security `restricted`. A looser level needs `psa: {level, reason}`. The `rbac` set creates the namespace.                                                                                                                                                                                                                               |

## 1. The package

`components/<category>/<x>/<x>.cue` (package name without dashes):

```cue
package x

import "github.com/homelab-selfuryon/platform-components/schema"

#X: {
	#cluster: schema.#Cluster
	#ref:     schema.#Ref
	let _ref = #ref // scope trap: `#ref: #ref` would refer to itself

	component: schema.#Component & {
		name:      "x"
		namespace: "x-system"
		set:       "platform"
		// dependsOn: ["cert-manager"]

		chart: schema.#Chart & {
			#ref: _ref                 // sets version and digest
			kind: "oci"                // "helm" | "oci" | "git"
			url:  "oci://ghcr.io/org/charts"   // oci: without the chart name
			name: "x"
			// path: "deploy/chart/x"  // git only; set version: #ref.version instead of #ref
			// includeCRDs: true       // charts that keep CRDs in crds/
		}
		values: {...}                  // typed, derive cluster specifics from #cluster
		// postRender: [{target: {...}, patch: "..."}]   // kustomize patches

		network: {
			ingress: [schema.Net.apiserverIn & {toPorts: [{ports: [{port: "9443", protocol: "TCP"}]}]}]
			egress: [schema.Net.apiserverOut]
		}

		// Cluster-scoped objects the render may contain; exact names for ClusterRole(Binding)s.
		whitelist: [
			schema.#CRD & {names: ["*.x.example"]},
			schema.#ClusterRole & {names: ["x-controller"]},
			schema.#ClusterRoleBinding & {names: ["x-controller"], bind: []},
		]

		manifests: scoped: "x-system": certificate: "x-tls": spec: {...}   // plain objects
	}
}
```

Rules the render and the policies enforce:

- Every namespace gets a generated default-deny CiliumNetworkPolicy (egress DNS only) and the
  component's own policy: declare what it needs (`schema.Net.*` helpers) or it cannot talk.
- The render's cluster-scoped objects must match the whitelist (`cue cmd check`). Find them with
  `python3 scripts/cluster_scoped.py out/<cluster> <component>` after a first render.
- Namespaced objects stay in `namespace` and `extraNamespaces` (a chart that writes elsewhere:
  `targetNamespace: false`, `extraNamespaces`, and `rbac.namespaced` for least privilege).
- Helm hooks: install hooks become ordinary objects (Jobs get Flux's force-recreate annotation),
  upgrade/delete/test hooks are dropped (see `apply_hook_policy` in `scripts/render_component.py`).
- Images name their registry (`security.allowedRegistries`), a tag other than `latest` or a digest.

## 2. Version

Add to `registry/latest.json` (Renovate keeps it current), field order matters for its regex manager
(`name, datasource, package, [registry], version, [digest]`):

```json
{
  "name": "x",
  "datasource": "docker",
  "package": "ghcr.io/org/charts/x",
  "version": "1.2.3",
  "digest": "sha256:..."
}
```

`digest` for OCI charts: `oras resolve ghcr.io/org/charts/x:1.2.3` (Helm then verifies the content).
Datasources: `helm` (+ `"registry": "<repo url>"`), `docker`, `github-tags`, `github-releases`.
Then `cue cmd promote -t to=<cluster> -t components=x` writes it into `clusters/<cluster>/pins.json`.

## 3. Wire it into the cluster

`clusters/defaults.cue`, in `#Platform.components` (aliased import, the component name as key):

```cue
x: (app_x.#X & {#cluster: config, #ref: versions.x}).component
```

Per-cluster values: `cluster: components: x: values: foo: "bar"` in `clusters/<c>/cluster.cue`.

## 4. Verify

```bash
bash scripts/cue-vet.bash
cue cmd render -t cluster=alpha-01       # runs helm template (needs network)
cue cmd check  -t cluster=alpha-01
bash scripts/kyverno-check.sh alpha-01   # policies over the render
kubeconform -ignore-missing-schemas -summary out/alpha-01/*/components/*/manifests.yaml
```

Render twice and `diff -r`: a chart that generates random values (`genCA`, `randAlphaNum`) makes the
artifact change on every release.
