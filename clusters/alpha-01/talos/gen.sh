#!/usr/bin/env bash
# Generates the alpha-01 machine config and talosconfig into .secrets/talos/alpha-01 (or $OUT_DIR).
# The cluster secrets (secrets.yaml) are generated on first run and never leave that directory: it
# is git-ignored, back it up offline (docs/bootstrap.md). Nothing secret is ever committed.
#
# Inputs:
#   NODE      node address (also the Kubernetes API endpoint), must be inside nodeIP.validSubnets of
#             patches/node.yaml (default: a placeholder)
#   OUT_DIR   output directory (CI renders with throwaway secrets)
#   SECRETS   the cluster secrets to use (default: $OUT_DIR/secrets.yaml, generated if missing);
#             set it to render into a scratch OUT_DIR with the real secrets (`apply-config --dry-run`)
#   LOCAL     extra patch with what must not be public, like the install disk's serial
#             (default: .secrets/talos/<cluster>/local.yaml, used when it exists)
#   ENCRYPT   1 adds patches/encryption.yaml (TPM-sealed LUKS2); only for a fresh install with
#             Secure Boot on, Talos does not encrypt existing volumes
set -euo pipefail

CLUSTER=alpha-01
NODE="${NODE:-2001:db8:1::10}"
ENDPOINT="https://[${NODE}]:6443"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(git -C "$here" rev-parse --show-toplevel)"
out="${OUT_DIR:-$root/.secrets/talos/$CLUSTER}"
secrets="${SECRETS:-$out/secrets.yaml}"
local_patch="${LOCAL:-$root/.secrets/talos/$CLUSTER/local.yaml}"
mkdir -p "$out"

if [[ ! -f $secrets ]]; then
  talosctl gen secrets -o "$secrets"
fi
extra=()
if [[ ${ENCRYPT:-0} == 1 ]]; then
  extra+=(--config-patch "@$here/patches/encryption.yaml")
fi
if [[ -f $local_patch ]]; then
  extra+=(--config-patch "@$local_patch")
fi

talosctl gen config "$CLUSTER" "$ENDPOINT" \
  --with-secrets "$secrets" \
  --output-types controlplane,talosconfig \
  --with-docs=false \
  --with-examples=false \
  --config-patch "@$here/patches/kubernetes.yaml" \
  --config-patch "@$here/patches/node.yaml" \
  --config-patch "@$here/patches/network.yaml" \
  --config-patch "@$here/patches/storage.yaml" \
  "${extra[@]}" \
  --output "$out" \
  --force

talosctl --talosconfig "$out/talosconfig" config endpoint "$NODE"
talosctl --talosconfig "$out/talosconfig" config node "$NODE"

talosctl validate --mode metal --strict --config "$out/controlplane.yaml"
