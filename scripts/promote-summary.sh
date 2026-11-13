#!/usr/bin/env bash
# Markdown summary of a promotion: which component moves from which version to which.
#
#   promote-summary.sh <old pins.json> <new pins.json> <registry/latest.json> <target> <source>
#
# Versions are `1.2.3` or `1.2.3@sha256:...` (pins.json form); a digest is shortened to 12 hex
# characters. The package column comes from latest.json.
set -euo pipefail

old=${1:?old pins.json}
new=${2:?new pins.json}
latest=${3:?registry/latest.json}
to=${4:?target cluster}
from=${5:?source}

jq -r -n --slurpfile old "$old" --slurpfile new "$new" --slurpfile latest "$latest" \
  --arg to "$to" --arg from "$from" '
  def short: if . == null then "—" else (split("@") | .[0] + (if length > 1 then " `" + (.[1] | ltrimstr("sha256:"))[0:12] + "`" else "" end)) end;
  def pkg($n): ($latest[0].components[] | select(.name == $n)) as $c
    | if $c == null then "" elif $c.datasource == "github-releases" then "[\($c.package)](https://github.com/\($c.package)/releases)"
      elif $c.datasource == "helm" then "`\($c.package)` (\($c.registry))" else "`\($c.package)`" end;
  ($old[0]) as $o | ($new[0]) as $n
  | [($o + $n) | keys_unsorted[] | select($o[.] != $n[.])] | unique as $changed
  | "Promotes `clusters/\($to)/pins.json` from `\($from)` (`cue cmd promote`).\n",
    if ($changed | length) == 0 then "No version changes."
    else
      "| Component | From | To | Package |",
      "| --- | --- | --- | --- |",
      ($changed[] as $k | "| `\($k)` | \($o[$k] | short) | \($n[$k] | short) | \(pkg($k)) |")
    end
'
