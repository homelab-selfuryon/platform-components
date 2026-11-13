#!/usr/bin/env python3
"""Whitelist check of a render (`cue cmd check -t cluster=<c>`).

Usage: check_whitelist.py out/<cluster>

Every cluster-scoped object a component renders must match one of the component's whitelist
entries (kind, API group, name or glob). Tenants and team components are held to the same rule.
Also checked:
  - namespaced objects stay in the component's namespaces (privileged components excepted);
  - ClusterRoleBindings reference only ClusterRoles of the component's own whitelist or the ones
    it may bind explicitly;
  - namespaced objects have a namespace.
HelmRelease components are checked on their approximate render (out/<c>/.approx), which is not
published: the HelmRelease itself and the chart's objects both have to pass.
Exit status 1 on any violation.
"""
import fnmatch
import json
import pathlib
import sys

import yaml

# libyaml when available: the pure-Python parser takes seconds on the CRDs.
_Loader = getattr(yaml, "CSafeLoader", yaml.SafeLoader)

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from kube_scope import crd_scopes, is_cluster_scoped  # noqa: E402


def load(path):
    if not path.exists():
        return []
    return [d for d in yaml.load_all(path.read_text(), Loader=_Loader) if d]


def group(doc):
    api = doc.get("apiVersion", "")
    return api.split("/")[0] if "/" in api else ""


def main():
    base = pathlib.Path(sys.argv[1])
    if not (base / ".work").is_dir():
        sys.exit(f"{base}: no render found; run `cue cmd render` first")
    metas = {}
    for m in sorted((base / ".work").glob("*/*/meta.json")):
        meta = json.loads(m.read_text())
        metas[(meta["set"], meta["name"])] = meta

    docs = {}
    for (s, n), meta in metas.items():
        d = load(base / s / "components" / n / "manifests.yaml")
        d += load(base / ".approx" / s / f"{n}.yaml")
        docs[(s, n)] = d
    crds = crd_scopes([x for d in docs.values() for x in d])

    errors = []
    for (s, n), meta in sorted(metas.items()):
        wl = meta.get("whitelist", [])
        allowed_ns = meta.get("allowedNamespaces", [])
        bindable = set(meta.get("bindable", []))
        for d in docs[(s, n)]:
            kind, name = d.get("kind"), d.get("metadata", {}).get("name", "")
            who = f"{s}/{n}: {kind} {name}"
            if is_cluster_scoped(d, crds):
                ok = any(
                    e["kind"] == kind
                    and e["apiGroup"] == group(d)
                    and any(fnmatch.fnmatchcase(name, pat) for pat in e["names"])
                    for e in wl
                )
                if not ok:
                    errors.append(f"{who}: cluster-scoped object not in the whitelist")
                if kind == "ClusterRoleBinding":
                    ref = d.get("roleRef", {})
                    if ref.get("kind") == "ClusterRole" and not (
                        ref["name"] in bindable
                        or any(
                            e["kind"] == "ClusterRole" and any(fnmatch.fnmatchcase(ref["name"], p) for p in e["names"])
                            for e in wl
                        )
                    ):
                        errors.append(f"{who}: binds ClusterRole {ref['name']}, which is neither whitelisted nor listed in bind")
            else:
                ns = d.get("metadata", {}).get("namespace")
                if not ns:
                    errors.append(f"{who}: namespaced object without a namespace")
                elif not meta.get("privileged") and not any(fnmatch.fnmatchcase(ns, p) for p in allowed_ns):
                    errors.append(f"{who}: namespace {ns} is not one of the component's namespaces {allowed_ns}")
    for e in errors:
        print(e, file=sys.stderr)
    total = sum(len(v) for v in docs.values())
    print(f"{len(metas)} components, {total} objects, {len(errors)} violations")
    sys.exit(1 if errors else 0)


main()
