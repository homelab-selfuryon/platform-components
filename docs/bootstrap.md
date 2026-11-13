# Bootstrap and break-glass

How a cluster goes from bare metal to "Flux applies signed artifacts, Argo CD syncs tenants", once,
by hand, over a path that does not depend on anything this repository sets up. The contract the
steps rely on is [delivery.md](https://github.com/homelab-selfuryon/meta/blob/main/delivery.md)
("Bootstrap"). Everything below is generic: no address, key or token of a real cluster is written
down anywhere in this repository.

Nothing here runs from CI. Never apply anything to a live cluster without deciding to.

## 0. Before you start

- The cluster's networks in `clusters/<cluster>/talos/patches/node.yaml` and `cluster.cue`
  (`trustedCIDRs`, `devices`; alpha-01 uses private ranges only and a fixed ULA node address,
  `talos/patches/network.yaml`). What must not be public, like the install disk's serial, goes into
  `.secrets/talos/<cluster>/local.yaml` (git-ignored), which `gen.sh` adds as a last patch.
- The artifacts exist: `gitops` has published `ghcr.io/homelab-selfuryon/gitops/<cluster>:main`, and
  `platform-components` has released the sets it points to (a merged release PR in `gitops`).
  The packages are public (Flux and Argo CD pull anonymously).
- `devenv --profile ops shell` (cue, helm, talosctl, kubectl, flux, age, ...; direnv enables the
  profile). No toolchain is installed globally.
- For disk encryption (`ENCRYPT=1 ./gen.sh`, `talos/patches/encryption.yaml`): Secure Boot enabled in
  the firmware and TPM 2.0 present, the keys are sealed to it, and a fresh install (Talos encrypts
  a volume only when it creates it). alpha-01 runs without it for now (meta `decisions.md`).
- A place for the **break-glass bundle**: an age-encrypted archive, the age identity on a hardware
  token, copies off the machine. It holds `talosconfig`, the admin `kubeconfig`, `secrets.yaml`
  (Talos cluster secrets), the OpenBao seal key and, later, the OpenBao recovery keys.

## 1. Talos

```bash
cd clusters/alpha-01/talos
NODE=<node address> ./gen.sh          # writes .secrets/talos/<cluster>/ (git-ignored): controlplane.yaml, talosconfig, secrets.yaml
# A running node: render elsewhere with its secrets and look at the difference first
NODE=<node address> OUT_DIR=$(mktemp -d) SECRETS=$PWD/../../../.secrets/talos/alpha-01/secrets.yaml ./gen.sh
talosctl apply-config --dry-run -f <that dir>/controlplane.yaml
talosctl apply-config --insecure -n <node address> -f ../../../.secrets/talos/alpha-01/controlplane.yaml
talosctl --talosconfig .secrets/talos/alpha-01/talosconfig bootstrap      # once: etcd
talosctl --talosconfig .secrets/talos/alpha-01/talosconfig kubeconfig .secrets/kubernetes/config
```

Move `.secrets/` into the break-glass bundle now. The `ops` profile points `TALOSCONFIG` and
`KUBECONFIG` at `.secrets/` (paths only). With encryption, the TPM-sealed volumes mean the node's
disks are useless if it is stolen; they also mean a motherboard or firmware change needs the
break-glass recovery path below.

The node stays `NotReady` until Cilium runs.

Changing the node address of a running node (the fixed ULA address in `network.yaml`, the node IP
in `node.yaml`): render with the new `NODE` into a scratch directory as above, `apply-config` it
through the current endpoint, then run `NODE=<new address> ./gen.sh` for the new talosconfig and
fetch the kubeconfig again; the API server certificate gains the new address.

## 2. Cilium, Flux, the `gitops` artifact

```bash
cue cmd bootstrap -t cluster=alpha-01          # writes out/alpha-01/bootstrap.yaml, no secrets
kubectl apply --server-side --force-conflicts -f out/alpha-01/bootstrap.yaml
# Custom resources (FluxInstance, OCIRepository, Kustomization) are rejected until the CRDs of the
# Flux Operator exist: wait for them, then apply the same file again.
kubectl wait --for condition=established --timeout=2m crd/fluxinstances.fluxcd.controlplane.io
kubectl apply --server-side --force-conflicts -f out/alpha-01/bootstrap.yaml
```

What it contains: the `flux-system` namespace, Cilium and Flux Operator (the same render as the
`cilium` and `flux-operator` components, so Flux adopts them without a diff), the FluxInstance
(multi-tenant lockdown), the ServiceAccounts `flux-privileged` (cluster-admin, for the core
components) and `gitops-root` (may create `OCIRepository` and `Kustomization` in `flux-system` and
nothing else), the OCIRepository `gitops` (cosign-verified: the certificate subject must be
`gitops/.github/workflows/publish.yaml@refs/heads/main`) and the root Kustomization `gitops` (path `./flux`).

From here Flux applies the sets in order: `rbac` (namespaces, component ServiceAccounts and roles),
`system` (Cilium, Flux Operator, Kyverno, Gateway API CRDs, cert-manager, the internal CA),
`policy` (Kyverno policies, host firewall), `platform` (local-path, metrics-server, Envoy Gateway,
external-dns, CloudNativePG, the CSI driver, OpenBao and its CSI provider, Argo CD, ClusterIssuers,
Gateways), `tenants` (teams). Watch it:

```bash
flux get kustomizations -A
kubectl -n flux-system get ocirepositories
```

Roll the network policies out with `network.policyAudit: true` first (Cilium logs what it would
drop), check `cilium-dbg monitor -t policy-verdict` in the agent pod, then set it to `false` in
`cluster.cue`. Keep the Talos API (50000) and kube-apiserver (6443) reachable when editing
`host-firewall`.

`network.podAccessCIDRs` lets the operator's network reach every pod directly (the `pod-access`
CiliumClusterwideNetworkPolicy, an allow on top of the pods' own policies). The workstation needs a
route to the pod CIDR via the node, e.g. `ip -6 route add fd00:10:244::/56 via <node ULA>`; with a
Tailscale or NetBird exit node also a rule ahead of its table (`ip -6 rule add to fd00:10:244::/56
lookup main priority 5200`).

## 3. The OpenBao seal key

OpenBao unseals itself with a static key: the Secret `openbao-seal-key` (key `key`, 32 random bytes
as 64 hex characters). It is created by hand, from the break-glass bundle, and never exists in git.
The `openbao` Kustomization waits for it (the pod stays in `ContainerCreating`).

```bash
# Generate once, put the file into the break-glass bundle FIRST, then create the Secret from it.
umask 077
openssl rand -hex 32 > "$BUNDLE/openbao-seal-key"
kubectl -n openbao-system create secret generic openbao-seal-key --from-file=key="$BUNDLE/openbao-seal-key"
```

Lose the key and the data in OpenBao is gone: keep two offline copies. To rotate it, add the new key
as `current_key` and the old one as `previous_key` in the seal stanza (components/security/openbao).

## 4. Initialise OpenBao, configure it, give it the platform secrets

```bash
kubectl -n openbao-system exec openbao-0 -- bao operator init -recovery-shares=5 -recovery-threshold=3
```

Store the recovery keys and the initial root token offline (break-glass bundle, split between
people where there are any); revoke the root token once `platform-terraform/openbao` has created
real identities. Then, over the private access path to OpenBao:

```bash
cd ../platform-terraform/openbao && tofu apply     # Kubernetes auth, mounts, policies, roles
bao kv put kv/platform/alpha-01/cert-manager  api-token=<Cloudflare token, DNS edit on the zone>
bao kv put kv/platform/alpha-01/external-dns  api-token=<Cloudflare token, DNS edit on the zone>
```

Roles, ServiceAccounts and paths: [secrets.md](secrets.md). When the roles exist, the pods that
mount the secrets start, the Secrets are synced, the ClusterIssuers and Gateways become ready.

## 5. Check

```bash
flux get kustomizations -A                       # everything Ready
kubectl get clusterissuer,gateway -A
kubectl -n argocd-system get appproject                 # notes, notes-preview (and the locked default)
argocd app list                                  # devenv wrapper: core mode (previews: argocd-system)
kubectl get applications -A                      # staging/prod: argocd-<team>
kubectl get ns -l homelab-selfuryon.github.io/team
```

## Day 2

- Component or policy change: PR here; its checks render every cluster, check the whitelists and
  show the object diff; merge releases the changed sets and opens the PR in `gitops`.
- New versions: Renovate edits `registry/latest.json`; the Promote workflow (or
  `cue cmd promote -t to=alpha-01`) copies them into `clusters/alpha-01/pins.json`. Promote to the
  next cluster with `-t from=alpha-01 -t to=<next>`.
- Onboarding a team: a file in `teams/` ([teams.md](teams.md)).
- Rollback: revert the PR in `gitops` that moved the digest.

## Break-glass

For when the normal path is gone: GitHub, GHCR, the private access network, or Flux itself.

- **What it is.** The age-encrypted bundle of section 0: `talosconfig` (Talos API, can reset the
  node), admin `kubeconfig` (members of `system:masters`, which the admission policies treat as
  break-glass), the Talos secrets, the OpenBao seal key and recovery keys. The age identity lives on
  a hardware token; there is no copy on a networked machine.
- **Path.** Over the home LAN to the node's Talos API (50000) and kube-apiserver (6443); both are
  allowed from `trustedCIDRs` by the host firewall and from nowhere else. It does not use the
  private access network, GitHub or any controller in the cluster.
- **Using it.** Decrypt into a temporary directory on a trusted machine, do the minimum, delete the
  directory. Every use is written down (date, reason, what was changed) and reviewed afterwards; the
  API audit log shows `system:masters` activity. Anything changed by hand is put back into git
  afterwards: Flux reverts drift on its next reconciliation anyway.
- **Flux stuck.** `flux suspend kustomization <name>` to stop a component, fix the source, `flux
resume`. A broken set artifact is rolled back by reverting its digest in `gitops`; if `gitops` is
  unreachable, re-apply `bootstrap.yaml` pointing the OCIRepository at a known-good tag.
- **Tenant emergency (exec into a pod).** Tenants cannot exec, attach or port-forward; break-glass
  can, and is audited. Prefer logs and a new revision.
- **After use.** If the bundle was exposed to anything less than a trusted machine: rotate. Talos
  (new cluster secrets or `talosctl rotate-ca`), kubeconfig (new admin certificate), OpenBao (rekey
  the recovery keys, rotate the seal key as in section 3), and the tokens stored in OpenBao.
- **Revocation is rehearsed.** At least once a year: restore the bundle on a clean machine, reach the
  API, rotate one credential of each kind and delete the restored copy.

Open items outside this repository: the private access network and the break-glass hardware token
procedure are described in `meta` ([decisions](https://github.com/homelab-selfuryon/meta/blob/main/decisions.md)).
