#!/usr/bin/env python3
"""Lists the cluster-scoped objects of every component of a render (to write whitelists).

Usage: cluster_scoped.py out/<cluster> [component...]
"""
import json
import pathlib
import sys

import yaml

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from kube_scope import crd_scopes, is_cluster_scoped  # noqa: E402

base = pathlib.Path(sys.argv[1])
only = set(sys.argv[2:])
docs = {}
for m in sorted((base / ".work").glob("*/*/meta.json")):
    meta = json.loads(m.read_text())
    n = meta["name"]
    d = []
    for f in (base / meta["set"] / "components" / n / "manifests.yaml", base / ".approx" / meta["set"] / f"{n}.yaml"):
        if f.exists():
            d += [x for x in yaml.safe_load_all(f.read_text()) if x]
    docs[n] = d
crds = crd_scopes([x for v in docs.values() for x in v])
for n, d in docs.items():
    if only and n not in only:
        continue
    print(f"== {n}")
    kinds = {}
    for x in d:
        if is_cluster_scoped(x, crds):
            kinds.setdefault(x["kind"], []).append(x["metadata"]["name"])
    for k, names in sorted(kinds.items()):
        print(f"  {k}: {names}")
