# CLAUDE.md

Platform repository of the homelab-selfuryon org: clusters, platform components, Kyverno policies and
team onboarding, written in CUE, rendered in CI (`helm template`), released as one signed OCI
artifact per cluster and set, delivered by Flux (Argo CD only syncs tenants). The contract with `gitops`, `github-workflows` and `platform-kit` is
`meta/delivery.md` ("Platform layout", "Flux object names", "CI interfaces", "Cluster-side names"):
change it there in the same session as here.

## Layout

```
schema/        #Cluster, #Component, #Chart, #Allow (whitelist), typed manifests (types.cue)
registry/      latest.json (Renovate) + #Resolve
render/        #Rendered: component -> Kustomization + plain objects + meta; #Complete adds network policies
components/<category>/<name>/   one package per component: #X: {#cluster, #ref, component: schema.#Component & {...}}
policies/      Kyverno CEL policies, one file per policy (`_policy: "<name>"`, values from `#ctx`: context.cue);
               whitelists/ServiceAccounts/Kustomization names come from the components
teams/         teams/<name>.cue (data) + schema.cue + component.cue (render of `team-<name>`)
bootstrap/     #Bootstrap (flux-privileged, gitops-root, OCIRepository gitops, root Kustomization)
clusters/      defaults.cue (#Platform: all components), clusters.cue (registry), <c>/{cluster.cue,pins.json,talos/}
crd/           generated schemas (Cilium, Flux Operator, Kyverno policies); see the crd-generation skill
ext_tool.cue   clusters | render | check | bootstrap | promote
scripts/       render_component.py (helm + patches + hook policy), check_whitelist.py, kyverno-check.sh, ...
docs/          bootstrap.md (+ break-glass), secrets.md, gateways.md, teams.md
```

## Commands

```bash
devenv shell -- bash scripts/cue-vet.bash                 # cue fmt --check + vet each package (not `cue vet ./...`)
devenv shell -- cue cmd render -t cluster=alpha-01        # needs network (helm); ~1-2 min
devenv shell -- cue cmd check  -t cluster=alpha-01
devenv shell -- cue cmd bootstrap -t cluster=alpha-01
devenv shell -- cue cmd promote -t to=alpha-01 [-t from=latest] [-t components=cilium,kyverno]
devenv shell -- bash scripts/kyverno-check.sh alpha-01    # rendered policies over the rendered objects
devenv --profile ops shell -- kubectl ...                 # cluster tools (talosctl, flux, argocd, ...): profile `ops`
```

## Rules

- Conventional Commits, `!` for breaking changes; signed commits. Never touch a live cluster
  (`kubectl apply`, `talosctl apply-config`, `cue cmd bootstrap | kubectl apply`) without the user's go-ahead.
- Public repository: no secrets, no public addresses, disks, serials or MACs. alpha-01's private
  networks (ULA, LAN) and its domain `homelab.ys7.me` are committed by decision; other examples use
  placeholders (`homelab.example`, 192.0.2.0/24, 2001:db8::/32). Secrets only in OpenBao; the seal key is
  created by hand at bootstrap.
- A component declares: `set`, `namespace` (`<name>-system`), `psa` (restricted unless a reason is
  given), `privileged` (+ `reason`), `whitelist` (exact names for ClusterRole(Binding)s), `network`,
  chart + typed `values` (OCI charts by digest) and/or plain `manifests`, `dependsOn`,
  `variant` (`helmrelease` needs `variantReason`). Skill: `add-component`.
- A new cluster-scoped kind or name in a render fails `cue cmd check` until the whitelist lists it:
  `python3 scripts/cluster_scoped.py out/<cluster> <component>` shows what a render contains. Do not
  widen a whitelist to make a check pass without understanding the object.
- A RoleBinding to a Role of the same component needs `bind` on that Role's name in the
  component's `rbac` (`resourceNames`): Flux dry-runs all objects before creating any, and without
  `bind` the API server looks the Role up for its escalation check and fails with "not found".
  The offline checks cannot see this.
- Renaming a component's namespace: the `rbac` set deletes the old namespace with everything in it,
  and the component's Kustomization then cannot prune its old objects (403: its ServiceAccount has
  no rights there any more) and stays not Ready. Clear its inventory once, never delete the
  Kustomization (prune would remove the new install):
  `kubectl -n flux-system patch kustomization <name> --subresource=status --type=json -p '[{"op":"remove","path":"/status/inventory"}]'`.
- devenv: the base shell is what CI needs (render, check, Kyverno) and what CI caches; cluster and
  release tools live in the `ops` profile (`.envrc` enables it). A tool CI needs goes into the base.
- Versions: `registry/latest.json` (Renovate) -> `cue cmd promote` -> `clusters/<c>/pins.json`.
  Field order in latest.json is a Renovate regex contract.
- Rendering must stay deterministic: render twice and `diff -r out/<c>` (hidden dirs excluded)
  after changing a chart's values.
- Releases and `releases.json` are in `gitops`, not here. CI logic is in `github-workflows`;
  `.github/workflows/` only calls it.
- Workflows: actions pinned by SHA, `persist-credentials: false`, no `${{ }}` in `run:` (use `env:`),
  minimal permissions; `zizmor .github/workflows` and `actionlint`.

## CUE traps (details in the cue-expert skill)

`#ref: #ref` refers to itself (use `let _ref = #ref`); a loop variable named `kind` is shadowed by a
field `kind`; an import named like a field is shadowed (alias imports); `list.UniqueItems` returns a
bool; `rbac` and `kyverno-policies` are built from the other components and must not contain each
other (see `_base` in `clusters/defaults.cue`). The module is language v0.18.0, evaluated by the v0.18.0-rc.4 binary that `devenv.nix` installs (drop the override when nixpkgs has v0.18).

## Policies

CEL policies (`policies.kyverno.io/v1`: ValidatingPolicy, ImageValidatingPolicy, GeneratingPolicy,
DeletingPolicy), Enforce; `kyverno.io/v1 ClusterPolicy` is deprecated, add none. Test expressions with
`scripts/kyverno-check.sh` (it type-checks them): policies that read `request.userInfo` run once per
component with `--userinfo` as its Flux ServiceAccount; every run must end with no failures and no
errors. The CLI does not apply policies to Kyverno's own policy kinds, so `component-whitelist` on
`kyverno-policies` itself is only enforced in the cluster. ClusterRoles a policy needs (aggregated to a Kyverno
controller) go under `clusterRole` of its `_policy` entry and ship in `kyverno-policies-rbac` (set
`platform`): by then the new `component-whitelist` knows their names. The cost: a new
GeneratingPolicy with `generateExisting` runs once when it arrives, before its ClusterRole, gets 403
and does not retry; only new triggers generate. Existing objects need a later change to the policy
(or, with the user's go-ahead, a restart of the background controller). Tenant namespaces are the ones with the label `homelab-selfuryon.github.io/team`;
admission selects on that label and on `.../env`, which only the platform sets.
