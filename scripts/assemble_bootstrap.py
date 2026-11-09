#!/usr/bin/env python3
"""Assembles out/<cluster>/bootstrap.yaml from the pieces `cue cmd bootstrap` rendered.

Order: the flux-system Namespace, Cilium, Flux Operator (with the FluxInstance), then the
ServiceAccounts, RBAC, OCIRepository and Kustomization of `gitops`. Custom resources come before
their CRDs are established on the first apply: apply twice (docs/bootstrap.md).
"""
import pathlib
import sys

import yaml

base = pathlib.Path(sys.argv[1])


def load(p):
    return [d for d in yaml.safe_load_all(p.read_text()) if d]


objects = load(base / ".bootstrap" / "objects.yaml")
namespaces = [d for d in objects if d["kind"] == "Namespace"]
rest = [d for d in objects if d["kind"] != "Namespace"]
docs = namespaces + load(base / ".bootstrap/cilium/manifests.yaml") + load(base / ".bootstrap/flux-operator/manifests.yaml") + rest
(base / "bootstrap.yaml").write_text("".join("---\n" + yaml.safe_dump(d, sort_keys=True, width=1 << 20) for d in docs))
print(f"{base}/bootstrap.yaml: {len(docs)} objects")
