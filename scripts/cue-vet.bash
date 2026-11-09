#!/usr/bin/env bash
# Vets every CUE package of the repository, one cue process per package, in parallel.
# (`cue vet ./...` evaluates everything in one process and fails on directories that hold
# two packages, like clusters/.)
set -euo pipefail

echo "### cue fmt --check"
cue fmt --check ./...

echo "### cue vet, every package"
pkgs=$(
  while IFS= read -r dir; do
    # The root package only holds ext_tool.cue, exercised by `cue cmd`.
    [[ $dir == "." ]] && continue
    # shellcheck disable=SC2013
    for pkg in $(grep -h "^package " "$dir"/*.cue 2>/dev/null | awk '{print $2}' | sort -u); do
      echo "$dir:$pkg"
    done
  done < <(find . -name "*.cue" -not -path "./cue.mod/*" -not -path "./out/*" -exec dirname {} \; | sort -u)
)

echo "$pkgs" | xargs -P "$(getconf _NPROCESSORS_ONLN)" -n 1 cue vet -c=false
echo "Vet checks passed"
