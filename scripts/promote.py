#!/usr/bin/env python3
"""Promotion of component versions into a cluster's pins.json (`cue cmd promote`). Standard library only.

    promote.py --pins clusters/<c>/pins.json --latest registry/latest.json [--body <file>] < input.json

The input is `_promote.input` of ext_tool.cue: target, source, offered ({name: version} of the
source), pins (the target's pins.json), resolved (names the target runs), named, excluded,
allowMajor, ignoreHolds, holds ({name: {reason, since, until?}}, registry/promotion.cue) and the
target's freeze ({reason, since, until?}) if it has one. Versions are "1.2.3" or "1.2.3@sha256:...".

Considered: the `named` components if any, else every component the target resolves; minus
`excluded`. A considered component moves to the offered version unless one of these says no:

  freeze     the target is frozen                                 ignoreHolds overrides
  hold       registry/promotion.cue holds the component           ignoreHolds overrides
  downgrade  the offered version is older than the pin            nothing: roll back by editing pins.json
  major      the first number changes (18.7 -> 19.0)              named, with allowMajor
  variant    the suffix changes (18.7-system-trixie ->            named
             18.7-standard-trixie, 1.2.3-rc.1 -> 1.2.3)
  unparsed   a version is not <n>[.<n>...][-suffix] (v allowed)   named

The same version with another digest moves (the tag was rebuilt). A freeze or hold whose `until`
has passed no longer applies. Major means the first number only: 0.29 -> 0.30 moves like a minor
(charts at 0.x bump the minor on every release). A named component the target does not pin yet is
added. Existing pins keep their order, new ones are appended.
"""

from __future__ import annotations

import argparse
import datetime
import json
import pathlib
import re
import sys
from dataclasses import dataclass

_VERSION = re.compile(r"^v?(\d+(?:\.\d+)*)(?:-([0-9A-Za-z.-]+))?$")


@dataclass(frozen=True)
class Version:
    core: tuple[int, ...]
    suffix: str | None
    digest: str | None


def parse(s: str) -> Version | None:
    """`1.2.3`, `v1.2.3`, `18.7-system-trixie@sha256:...`; None for anything else (`latest`, `main`)."""
    tag, _, digest = s.partition("@")
    m = _VERSION.match(tag)
    if not m:
        return None
    return Version(tuple(int(p) for p in m[1].split(".")), m[2], digest or None)


def _padded(a: tuple[int, ...], b: tuple[int, ...]) -> tuple[tuple[int, ...], tuple[int, ...]]:
    n = max(len(a), len(b))
    return a + (0,) * (n - len(a)), b + (0,) * (n - len(b))


def _active(hold: dict | None, today: str) -> bool:
    return bool(hold) and ("until" not in hold or today <= hold["until"])


def _hold_text(hold: dict) -> str:
    until = f", until {hold['until']}" if "until" in hold else ""
    return f"{hold['reason']} (since {hold['since']}{until})"


@dataclass
class Plan:
    moves: dict[str, tuple[str | None, str]]  # name -> (pinned or None, new)
    skipped: dict[str, tuple[str | None, str, str]]  # name -> (pinned, offered, reason)
    pins: dict[str, str]  # the new pins.json


def gate(name: str, old: str, new: str, *, named: bool, allow_major: bool) -> str | None:
    """Why `name` must not move from `old` to `new` (None: it may). Holds and freezes are not here."""
    o, n = parse(old), parse(new)
    if o is None or n is None:
        return None if named else f"`{old if o is None else new}` is not a version; name it to move it"
    oc, nc = _padded(o.core, n.core)
    if nc < oc:
        return "downgrade; roll back by editing pins.json"
    if o.suffix != n.suffix:
        return None if named else "the suffix changes; name it to move it"
    if n.core[0] != o.core[0]:
        if not (named and allow_major):
            return f"new major version {n.core[0]}; name it with allow_major to move it"
    return None


def plan(inp: dict, today: str) -> Plan:
    offered: dict[str, str] = inp["offered"]
    pins: dict[str, str] = inp["pins"]
    named: list[str] = inp.get("named") or []
    excluded: list[str] = inp.get("excluded") or []
    ignore_holds = bool(inp.get("ignoreHolds"))
    allow_major = bool(inp.get("allowMajor"))
    holds: dict = inp.get("holds") or {}
    freeze = inp.get("freeze")

    unknown = [n for n in named + excluded if n not in offered and n not in pins]
    if unknown:
        raise SystemExit(f"unknown components: {', '.join(unknown)}")
    missing = [n for n in named if n not in offered]
    if missing:
        raise SystemExit(f"{inp['source']} does not offer: {', '.join(missing)}")
    if allow_major and not named:
        raise SystemExit("allow_major needs the components named (-t components=a,b)")

    names = named or inp["resolved"]
    moves, skipped = {}, {}
    for name in names:
        if name in excluded or name not in offered:
            continue
        old, new = pins.get(name), offered[name]
        if old == new:
            continue
        reason = None
        if _active(freeze, today) and not ignore_holds:
            reason = f"cluster frozen: {_hold_text(freeze)}"
        elif _active(holds.get(name), today) and not ignore_holds:
            reason = f"held: {_hold_text(holds[name])}"
        elif old is not None:
            reason = gate(name, old, new, named=name in named, allow_major=allow_major)
        if reason:
            skipped[name] = (old, new, reason)
        else:
            moves[name] = (old, new)

    out = {n: moves[n][1] if n in moves else v for n, v in pins.items()}
    out.update({n: m[1] for n, m in moves.items() if n not in pins})
    return Plan(moves, skipped, out)


def _short(v: str | None) -> str:
    if v is None:
        return "—"
    tag, _, digest = v.partition("@")
    return f"{tag} `{digest.removeprefix('sha256:')[:12]}`" if digest else tag


def _package(name: str, latest: dict) -> str:
    c = next((c for c in latest.get("components", []) if c.get("name") == name), None)
    if c is None:
        return ""
    if c["datasource"] == "github-releases":
        return f"[{c['package']}](https://github.com/{c['package']}/releases)"
    if c["datasource"] == "helm":
        return f"`{c['package']}` ({c.get('registry', '')})"
    return f"`{c['package']}`"


def describe(p: Plan, inp: dict, latest: dict) -> str:
    """Markdown for the pull request: what moves, what was skipped and why."""
    lines = [f"Promotes `clusters/{inp['target']}/pins.json` from `{inp['source']}` (`cue cmd promote`).", ""]
    if p.moves:
        lines += ["| Component | From | To | Package |", "| --- | --- | --- | --- |"]
        lines += [f"| `{n}` | {_short(o)} | {_short(v)} | {_package(n, latest)} |" for n, (o, v) in p.moves.items()]
    else:
        lines.append("No version changes.")
    if p.skipped:
        lines += ["", "### Skipped", "", "| Component | Pinned | Offered | Why |", "| --- | --- | --- | --- |"]
        lines += [f"| `{n}` | {_short(o)} | {_short(v)} | {r} |" for n, (o, v, r) in p.skipped.items()]
    return "\n".join(lines) + "\n"


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--pins", required=True, type=pathlib.Path, help="pins.json to rewrite")
    ap.add_argument("--latest", required=True, type=pathlib.Path, help="registry/latest.json (package names)")
    ap.add_argument("--body", type=pathlib.Path, help="write the pull request description here")
    ap.add_argument("--today", default=datetime.date.today().isoformat(), help="YYYY-MM-DD (tests)")
    args = ap.parse_args(argv)

    inp = json.load(sys.stdin)
    p = plan(inp, args.today)
    text = json.dumps(p.pins, indent=2, ensure_ascii=False) + "\n"
    if args.pins.read_text() != text:
        args.pins.write_text(text)
    if args.body:
        args.body.write_text(describe(p, inp, json.loads(args.latest.read_text())))

    print(f"{inp['target']} <- {inp['source']}:" + ("" if p.moves else " nothing to promote"))
    for n, (o, v) in p.moves.items():
        print(f"  {n}: {o or '(unpinned)'} -> {v}")
    for n, (o, v, r) in p.skipped.items():
        print(f"  skipped {n}: {o} -> {v}: {r}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
