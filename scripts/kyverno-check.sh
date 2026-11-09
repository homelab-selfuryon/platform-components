#!/usr/bin/env bash
# Runs the rendered Kyverno policies (out/<cluster>/policy/components/kyverno-policies) over every
# other rendered object of the cluster. Run `cue cmd render -t cluster=<c>` first.
#
#   scripts/kyverno-check.sh <cluster>
#
# `kyverno apply` needs the CRDs of every kind it sees: the ones in the render come from the render
# itself (variant A components: from their approximate render in .approx). Cilium installs its CRDs
# through the operator and Flux through the FluxInstance, both at runtime, so those are fetched from
# the releases pinned in clusters/<cluster>/pins.json.
set -euo pipefail

cluster=${1:?usage: kyverno-check.sh <cluster>}
base="out/$cluster"
policies="$base/policy/components/kyverno-policies/manifests.yaml"
[[ -f $policies ]] || {
  echo "$policies: not rendered" >&2
  exit 1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mapfile -t files < <(find "$base" -name manifests.yaml -not -path '*/.work/*' -not -path '*/.bootstrap/*' -not -path "$policies" | sort)

mapfile -t approx < <(find "$base/.approx" -name '*.yaml' 2>/dev/null | sort)

yq 'select(.kind == "CustomResourceDefinition")' "${files[@]}" "${approx[@]}" "$policies" >"$tmp/crds.yaml"
flux=$(jq -r '.flux' "clusters/$cluster/pins.json")
echo "---" >>"$tmp/crds.yaml"
curl -sfL "https://github.com/fluxcd/flux2/releases/download/${flux}/install.yaml" |
  yq 'select(.kind == "CustomResourceDefinition")' >>"$tmp/crds.yaml"
cilium=$(jq -r '.cilium | split("@")[0]' "clusters/$cluster/pins.json")
for crd in ciliumnetworkpolicies ciliumclusterwidenetworkpolicies; do
  echo "---" >>"$tmp/crds.yaml"
  curl -sfL "https://raw.githubusercontent.com/cilium/cilium/v${cilium}/pkg/k8s/apis/cilium.io/client/crds/v2/${crd}.yaml" >>"$tmp/crds.yaml"
done

args=()
for f in "${files[@]}" "${approx[@]}"; do args+=(--resource "$f"); done

# Policies that look at the admission request (userInfo, operation) can not be evaluated by the
# CLI: they show up as errors, not failures. `kyverno apply` exits 1 on errors too, so its exit
# code is ignored and the summary line decides: any failure, or no summary (a fatal error), fails
# the script.
kyverno apply "$policies" "${args[@]}" --crd-paths "$tmp/crds.yaml" | tee "$tmp/out.txt" || true
summary=$(grep -E '^pass: [0-9]+, fail: [0-9]+' "$tmp/out.txt" | tail -1)
if [[ -z $summary ]]; then
  echo "kyverno: no result summary, the run did not complete" >&2
  exit 1
fi
if [[ ! $summary =~ fail:\ 0, ]] || grep -q ' failed:' "$tmp/out.txt"; then
  echo "kyverno: policy failures above" >&2
  exit 1
fi
