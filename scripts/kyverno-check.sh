#!/usr/bin/env bash
# Runs the rendered Kyverno policies (out/<cluster>/policy/components/kyverno-policies) over the
# rendered objects of the cluster. Run `cue cmd render -t cluster=<c>` first.
#
#   scripts/kyverno-check.sh <cluster>
#
# Two kinds of runs (inputs prepared by scripts/kyverno_inputs.py):
#
#   static     policies that judge the object alone, over every object they match: component
#              manifests, the approximate render of variant A components, the sets' Kustomizations.
#   admission  policies that judge who sends the object (request.userInfo: component-whitelist,
#              component-namespaces, ...), once per non-privileged component as its Flux
#              ServiceAccount component-<name>, the way admission sees the component's apply.
#              The CLI does not apply policies to Kyverno's own policy kinds: what
#              kyverno-policies creates is only checked in the cluster.
#
# Every run must end with fail: 0 and error: 0. `kyverno apply` costs about objects x CRD size, so
# each run gets only the objects its policies match and the CRDs of those objects' kinds.
#
# CRDs: from the render (variant A components: their approximate render); Cilium's and Flux's are
# installed at runtime (operator, FluxInstance), so they come from the releases pinned in
# clusters/<cluster>/pins.json.
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

mapfile -t rendered < <(find "$base" -path "$base/.work" -prune -o -path "$base/.bootstrap" -prune -o -name '*.yaml' -print | sort)
yq 'select(.kind == "CustomResourceDefinition")' "${rendered[@]}" >"$tmp/crds.yaml"
flux=$(jq -r '.flux' "clusters/$cluster/pins.json")
echo "---" >>"$tmp/crds.yaml"
curl -sfL "https://github.com/fluxcd/flux2/releases/download/${flux}/install.yaml" |
  yq 'select(.kind == "CustomResourceDefinition")' >>"$tmp/crds.yaml"
cilium=$(jq -r '.cilium | split("@")[0]' "clusters/$cluster/pins.json")
for crd in ciliumnetworkpolicies ciliumclusterwidenetworkpolicies; do
  echo "---" >>"$tmp/crds.yaml"
  curl -sfL "https://raw.githubusercontent.com/cilium/cilium/v${cilium}/pkg/k8s/apis/cilium.io/client/crds/v2/${crd}.yaml" >>"$tmp/crds.yaml"
done

python3 -I "$(dirname "$0")/kyverno_inputs.py" "$base" "$tmp/crds.yaml" "$tmp"

# `kyverno apply` exits 1 on errors and failures alike and its output is long: the summary line
# decides. No summary means the run did not complete.
check() {
  local name=$1 out=$2 summary
  summary=$(grep -E '^pass: [0-9]+, fail: [0-9]+' "$out" | tail -1 || true)
  if [[ -z $summary ]]; then
    cat "$out" >&2
    echo "kyverno [$name]: no result summary, the run did not complete" >&2
    return 1
  fi
  if [[ ! $summary =~ fail:\ 0,.*error:\ 0, ]]; then
    grep -E -A3 ' (failed|error):?$|failed:|^Error' "$out" >&2 || cat "$out" >&2
    echo "kyverno [$name]: $summary" >&2
    return 1
  fi
  echo "kyverno [$name]: $summary"
}

status=0

args=()
for f in "$tmp"/static/resources/*.yaml; do args+=(--resource "$f"); done
kyverno apply "$tmp/static/policies.yaml" "${args[@]}" --crd-paths "$tmp/static/crds.yaml" \
  >"$tmp/static.out" 2>&1 || true
check static "$tmp/static.out" || status=1

for dir in "$tmp"/admission/*/; do
  n=$(basename "$dir")
  kyverno apply "$tmp/admission/policies.yaml" --resource "$dir/resources.yaml" \
    --crd-paths "$dir/crds.yaml" --userinfo "$dir/userinfo.yaml" >"$dir/out" 2>&1 || true
  check "component-$n" "$dir/out" || status=1
done

exit "$status"
