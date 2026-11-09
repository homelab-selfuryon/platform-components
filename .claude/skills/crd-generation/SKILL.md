---
name: crd-generation
description: Generate or regenerate CUE schemas under crd/ with `cue get crd`. Use when a component's custom resources need typing and the schema is not in the CUE Central Registry (cue.dev/x/crd/...) - covers where to get the CRD YAML, layout, the generate procedure, cleanup and stripping expensive matchN validators.
---

# CRD generation

First check the CUE Central Registry: `cue.dev/x/crd/<group>` exists for many projects (Flux:
`cue.dev/x/crd/fluxcd.io`, cert-manager: `cue.dev/x/crd/cert-manager.io`). Probe with
`curl -s https://registry.cue.works/v2/cue.dev/x/crd/<group>/tags/list` and prefer a registry module
(`cue mod get`, then import it) over generating.

Only when it is missing, generate a schema into `crd/`. Today: Cilium (`crd/cilium/v2`), Flux
Operator (`crd/fluxoperator/v1`), Kyverno policies (`crd/kyvernopolicies/v1`). Everything else
(Gateway API, Envoy Gateway, SecretProviderClass) is typed as `schema.#Raw` in `schema/types.cue`.

## Layout

```
crd/<short-name>/<version>/<kind>.cue      package <version>
```

One directory per CRD group, the version subdirectory matches `spec.versions[].name`. Import as
`kyverno_v1 "github.com/homelab-selfuryon/platform-components/crd/kyvernopolicies/v1"` and wire the
kind into `#GlobalTypes`/`#ScopedTypes` in `schema/types.cue`.

## Getting the CRD YAML

From the chart or release that `registry/latest.json` pins, not from a cluster:

```bash
mkdir -p /tmp/crds && cd /tmp/crds
helm template k oci://ghcr.io/kyverno/charts/kyverno --version <v> --include-crds \
  | yq 'select(.kind == "CustomResourceDefinition") | select(.spec.group == "policies.kyverno.io")' \
  | yq -s '"crd-" + .metadata.name'
for f in crd-*; do mv "$f" "$f.yaml"; done
```

## Procedure

```bash
(cd /tmp/crds && cue get crd --group <group> ./crd-<plural>*.yaml)     # writes <version>/<kind>.cue
cp /tmp/crds/v1/<kind>.cue crd/<short-name>/v1/

python3 scripts/crd/clean-crd.py crd/<short-name>/v1/<kind>.cue      # see below
python3 scripts/crd/strip-matchn.py [--presence crd/<short-name>/<version>/<kind>.cue]
cue fmt crd/... && bash scripts/cue-vet.bash
```

No experiment header: generated files compile at the module's language version.

## Cleanup (`scripts/crd/clean-crd.py`)

Drops the `import (...)` block and the validators that used it (`strings.MaxRunes(N) &`,
`list.MaxItems(N) &`, `time.Time` becomes `string`), the `_embeddedResource` embedding and block,
and the top-level `status?` (controller-owned); then `cue fmt`.

## matchN

CUE evaluates `matchN` by unifying a copy of the whole value with every schema in its list, so the
validators `cue get crd` emits for OpenAPI `oneOf`/`anyOf` and `x-kubernetes-int-or-string` can
dominate evaluation (mostly Cilium policies). `scripts/crd/strip-matchn.py` removes
`matchN(>=1, [int, string]) &` everywhere under `crd/`, and with `--presence` the required-fields-only
`matchN(...)` of kinds instantiated in bulk (this drops a check: restate what you rely on where the
type is applied). `crd/cilium/v2` is processed with `--presence` for both files.
