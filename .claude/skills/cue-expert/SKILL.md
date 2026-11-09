---
name: cue-expert
description: CUE language expert for platform-components — language v0.18.0, postfix aliases and strict embedding, the try experiment, the status of every CUE experiment, scope traps and the v0.18 pitfalls. Use when working with CUE files, schemas, or validation in this project.
---

# CUE Expert Mode

The module is at **language version v0.18.0** (`cue.mod/module.cue`), evaluated with the CUE
pre-release `devenv.nix` installs from the upstream tarball (v0.18.0-rc.3 until v0.18.0 reaches
nixpkgs; then the override goes). At v0.18.0 postfix aliases (`~(K,V)`, `self`) and strict embedding
(`X...`) are plain language: no experiment attribute is needed or wanted.

## CUE experiments

### File header

```cue
package mypackage
```

No attribute by default. Add `@experiment(try)` (before `package`, after `@extern(embed)` if present) only to a
file that uses `try`, `?` selectors, or `else`/`otherwise` on comprehensions — they fail without
it. Never add `aliasv2`/`explicitopen` (stable, no-ops). Generated CRDs under `crd/` carry no attribute.

### Status of every experiment (CUE v0.18.0-rc.3)

Source of truth: `cue help experiments`, or `internal/cueexperiment/{file,exp}.go` in
the CUE repo. A **per-file** experiment is enabled with `@experiment(name)` and tracks
the module's language version; once **stable** at that version it is always on. A
**global** experiment is set with `CUE_EXPERIMENT=name` (or `name=0` to disable one that
is on by default) and tracks the binary's version.

| per-file                                                                                 | preview | stable | here                           |
| ---------------------------------------------------------------------------------------- | ------- | ------ | ------------------------------ |
| `structcmp` — `==` on all values, unary `==`                                             | v0.14   | v0.15  | always on                      |
| `aliasv2` — postfix aliases `~X` / `~(K,V)`, predeclared `self`; prefix `X=` is rejected | v0.15   | v0.18  | always on (`schema/types.cue`) |
| `explicitopen` — strict embedding, postfix `X...` to open                                | v0.15   | v0.18  | always on                      |
| `try` — `try` clause, `a?` selectors, `else`, `otherwise`                                | v0.16   | —      | not used yet                   |
| `shortcircuit` — `&&` / `\|\|` skip the right operand                                    | v0.17   | —      | not used                       |
| `functions` — `func(...) -> T: body` literals, types, calls                              | v0.18   | —      | not used (preview)             |
| `openlists` — lists open like structs, `#[...]` / `#{...}` closed literals               | v0.18   | —      | do not adopt                   |

| global (`CUE_EXPERIMENT`)                                                                                     | preview | default | stable      | note                                                      |
| ------------------------------------------------------------------------------------------------------------- | ------- | ------- | ----------- | --------------------------------------------------------- |
| `formatv2` — rewritten `cue fmt`                                                                              | v0.18   | v0.18   | —           | alignment differs from older `cue fmt`                    |
| `yamlgoccy` — goccy-based YAML encoder/decoder                                                                | v0.18   | v0.18   | —           | writes non-BMP characters raw, quotes `0X1F`-like strings |
| `openapiv2` — whole-document OpenAPI import/export                                                            | v0.18   | —       | —           | not used                                                  |
| `modules`, `yamlv3decoder`, `decodeint64`, `embed`, `toposort`, `evalv3`, `keepvalidators`, `cmdreferencepkg` | ≤ v0.13 |         | v0.11–v0.16 | stable, cannot be turned off                              |

`@extern(embed)` (file embedding, `_x: _ @embed(file="x.json")`) is still a per-file
attribute and stays where JSON is embedded.

### Upgrading the language version

`cue fix --exp=<name>` migrates files while the module is still **below** the version
where the experiment is stable; afterwards raise `language.version` and drop the now
stable attributes. A file at a version where an experiment is stable cannot opt out.
Every CUE change is checked by comparing renders before/after (see Validation).

### Which preview experiments would help here

- **`try`**: the natural replacement for `if x != _|_ { ... }` guards over optional
  fields. Adopt per file when a component starts using optional config.
- **`functions`**: fits the "function by definition" helpers written as a struct with a
  parameter and an `out` field, called as `(#F & {#c: x}).out` — e.g. `#Kustomization`,
  `#HelmRelease` in `render/render.cue`. Semantics still change between previews: wait until
  it is stable. Component definitions (`#X: {#cluster, #version, component: ...}`) are
  templates, not functions: keep them as unification.
- **`shortcircuit`**: turn on in a file only when a condition like
  `a != _|_ && a.b == 1` is wanted; it changes the meaning of conditions whose right
  side carries an error.
- **`openlists`**: gives nothing (no list relies on being closed) and removes the
  length check that catches a mis-merged list.

---

## Postfix aliases and `self` (stable at v0.18)

```cue
[string]~(L,V)  // L = label (key), V = value; `_` ignores one
[string]~V      // value only (also written ~(V))
```

The manifest types use them to default `metadata.name` from the key and to push the
namespace down from the scope key (`schema/types.cue`):

```cue
#ScopedTypes: [string]~(TYPE,_): [string]~(ID,_): {
	kind:     *strings.ToTitle(TYPE) | string
	metadata: name: *ID | string
}

#Manifests: {
	scoped: [string]~(ns,_): [string]~(type,_): [string]~(name,_): {
		metadata: namespace: ns
	}
}
```

The old prefix form is a parse error at language v0.18:

```cue
ports: [ID=string]: #Port & {id: ID}        // ❌
ports: [string]~(ID,_): #Port & {id: ID}    // ✅
```

## Strict embedding and `X...` (stable at v0.18)

Embedding a closed value closes the embedding struct to that value's fields, exactly
as unifying with it does; `X...` opens a closed value on purpose:

```cue
A: {#Schema, field: "value"}    // same as #Schema & {field: "value"}
B: #Schema... & {extra: 1}      // explicitly opened
```

---

## v0.18 pitfalls

Constructs older CUE accepted that fail at v0.18 (seen in etherno-infra; none occur
here, do not introduce them):

1. **Selecting a struct out of a definition and adding a field to it.**
   `_cfg.storage? & {extra: true}` with `_cfg = #config` fails `field not allowed`:
   what a reference selects from a definition stays closed. Spell the fields out.
2. **A `let` inside a definition field that selects regular data** treats that data as
   closed and rejects fields added elsewhere. Declare the `let` on the enclosing struct,
   outside the definition.
3. **A `try` nested in another `try` that dereferences an absent optional field**
   reports `cyclic reference` (cue-lang/cue#4486). Use an `if x != _|_` guard for the
   inner one.

1 and 2 fail `cue vet`; 3 is lazy (vet passes, `cue cmd dump`/`yaml.Marshal` hits it),
so check CUE changes with both. The v0.18 YAML encoder writes non-BMP characters raw
and may quote strings differently: compare renders as objects, not bytes.

---

## Scope traps in this repo

### Self-reference inside a unification literal

```cue
// WRONG: the right-hand #ref is the inner field itself (top), not the outer one
chart: schema.#Chart & {#ref: #ref}

// RIGHT: bind the outer value first
let _ref = #ref
chart: schema.#Chart & {#ref: _ref}
```

Same for `#cluster: #cluster`, `#c: #c`. Components all start with `let _ref = #ref`.

### A field named like a variable shadows it

`{kind: kind}`, `for kind in ... {kind: kind}` and `component.manifests.global[kind]` inside a struct
that has a `kind` field all read the field. Name loop variables differently (`kd`, `key`). Same for
fields named like imports (`bootstrap`, `clusters`): alias the import (`pkg_bootstrap`, `all_clusters`).

### Fields of a definition are not in lexical scope of a literal unified with it

```cue
#Platform: #Cluster & {
	config:   _        // declare to bring #Cluster's fields into scope
	versions: _
	components: cilium: (app_cilium.#Cilium & {#cluster: config, #ref: versions.cilium}).component
}
```

### Components that are built from each other

`rbac` is derived from every other component, and `kyverno-policies` too. Pass them only the
components they need (`_base`, `_noRBAC` in `clusters/defaults.cue`): a component value that contains
itself is a structural cycle, even if only metadata is read.

### Stdlib surprises

- `list.UniqueItems` returns a bool, it does not dedupe: use a struct (`{for x in l {(x): true}}`).
- `list + list` is deprecated: `list.Concat([a, b])`.
- Struct field order is not a contract: `pins.json` is written from an ordered list by hand.

### Undefined fields in comparisons

`_current[n] != _source[n]` with `_current[n]` absent is an error, not false: guard with
`_current[n] != _|_` first, in a separate `if` clause.

### CEL embedded in CUE

Policy expressions are strings: test them with `kyverno apply` (it type-checks them). Optional
index is `labels[?'key'].orValue('')`, not `labels.?"key"`; maps with values of different types
need `json.unmarshal(r'...')` (raw string) instead of a literal.

---

## Manifest typing (evaluator performance)

Re-applying a closed definition on the same data multiplies typo-check work, so apply `#Manifests`
where a tree is produced (a component's `manifests`, `render.#Complete`) and not again at
intermediate levels. Never type a manifest tree with a disjunction. Marshal each object
(`yaml.Marshal(object)`) instead of collecting objects into a list (`render.#Objects`).

---

## Validation

```bash
bash scripts/cue-vet.bash                     # cue fmt --check and every package (not `cue vet ./...`)
cue cmd render -t cluster=alpha-01            # out/alpha-01/<set>/...
cue cmd check  -t cluster=alpha-01            # whitelist check of the render
```

After a refactor or a CUE upgrade, render before and after and compare the directories
(`diff -r`): the render is deterministic, so any difference is real.

## Common mistakes

- Star inside quotes: `"*v1" | "v2"` is wrong, `*"v1" | "v2"` is right.
- `if field {` checks truthiness; presence is `if field != _|_ {`.
- Values a cluster must be able to override are defaults in the component, otherwise the override
  conflicts. Unification cannot remove a component: start from a smaller definition.
