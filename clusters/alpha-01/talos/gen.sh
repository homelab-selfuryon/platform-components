#!/usr/bin/env bash
# Generates the alpha-01 machine config and talosconfig into .secrets/talos/alpha-01 (or $OUT_DIR).
# The cluster secrets (secrets.yaml) are generated on first run and never leave that directory: it
# is git-ignored, back it up offline (docs/bootstrap.md). Nothing secret is ever committed.
#
# Inputs (placeholders by default, RFC 3849 documentation prefix):
#   NODE      node address (also the Kubernetes API endpoint), must be inside nodeIP.validSubnets of
#             patches/node.yaml
#   OUT_DIR   output directory (CI renders with throwaway secrets)
set -euo pipefail

CLUSTER=alpha-01
NODE="${NODE:-2001:db8:1::10}"
ENDPOINT="https://[${NODE}]:6443"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(git -C "$here" rev-parse --show-toplevel)"
out="${OUT_DIR:-$root/.secrets/talos/$CLUSTER}"
mkdir -p "$out"

if [[ ! -f "$out/secrets.yaml" ]]; then
  talosctl gen secrets -o "$out/secrets.yaml"
fi

talosctl gen config "$CLUSTER" "$ENDPOINT" \
  --with-secrets "$out/secrets.yaml" \
  --output-types controlplane,talosconfig \
  --with-docs=false \
  --with-examples=false \
  --config-patch "@$here/patches/kubernetes.yaml" \
  --config-patch "@$here/patches/node.yaml" \
  --config-patch "@$here/patches/network.yaml" \
  --config-patch "@$here/patches/storage.yaml" \
  --output "$out" \
  --force

talosctl --talosconfig "$out/talosconfig" config endpoint "$NODE"
talosctl --talosconfig "$out/talosconfig" config node "$NODE"

talosctl validate --mode metal --strict --config "$out/controlplane.yaml"
