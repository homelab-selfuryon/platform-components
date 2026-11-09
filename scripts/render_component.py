#!/usr/bin/env python3
"""Renders one component into its directory of the set artifact.

Usage: render_component.py <workdir> <outdir> [<approx-file>]

<workdir> holds what `cue cmd render` wrote: meta.json, values.json (charts), plain.yaml (the
plain objects), patches.json (post-render kustomize patches). <outdir> receives manifests.yaml.

Variant B (render): helm template + plain objects + patches -> manifests.yaml.
Variant A (helmrelease): manifests.yaml is the plain objects (HelmRelease and its source); the
chart is rendered to <approx-file> only, for diffs and checks, and never published. Its hooks are
kept: helm-controller runs them.
"""
import json
import os
import pathlib
import subprocess
import sys
import tempfile

import yaml

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from kube_scope import crd_scopes, is_cluster_scoped  # noqa: E402

root = pathlib.Path(__file__).resolve().parent.parent


def run(cmd, **kw):
    p = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if p.returncode != 0:
        sys.exit(f"{' '.join(cmd)}\n{p.stderr}")
    return p.stdout


def helm_env():
    # Never touch the user's Helm configuration: caches and repositories live under out/.helm.
    base = pathlib.Path(os.environ.get("PLATFORM_HELM_HOME", root / "out" / ".helm"))
    env = dict(os.environ)
    for k, d in (("HELM_CACHE_HOME", "cache"), ("HELM_CONFIG_HOME", "config"), ("HELM_DATA_HOME", "data")):
        (base / d).mkdir(parents=True, exist_ok=True)
        env[k] = str(base / d)
    return env


def helm_template(meta, workdir):
    chart = meta["chart"]
    cmd = ["helm", "template", chart["release"]]
    tmp = None
    if chart["kind"] == "helm":
        cmd += [chart["name"], "--repo", chart["url"], "--version", chart["version"]]
    elif chart["kind"] == "oci":
        ref = f"{chart['url']}/{chart['name']}"
        if "digest" in chart:
            cmd += [f"{ref}@{chart['digest']}"]  # Helm verifies the content against the digest
        else:
            cmd += [ref, "--version", chart["version"]]
    elif chart["kind"] == "git":
        tmp = tempfile.TemporaryDirectory()
        run(["git", "clone", "--quiet", "--depth", "1", "--branch", chart["version"], chart["url"], tmp.name])
        cmd += [str(pathlib.Path(tmp.name) / chart["path"])]
    cmd += ["--namespace", meta.get("namespace", "default"), "--kube-version", meta["kubeVersion"], "--skip-tests"]
    for a in meta["apiVersions"]:
        cmd += ["--api-versions", a]
    values = workdir / "values.json"
    if values.exists():
        cmd += ["-f", str(values)]
    if chart["includeCRDs"]:
        cmd += ["--include-crds"]
    out = run(cmd, env=helm_env())
    if tmp:
        tmp.cleanup()
    return [d for d in yaml.safe_load_all(out) if d]


HOOK_ANNOTATIONS = ("helm.sh/hook", "helm.sh/hook-weight", "helm.sh/hook-delete-policy")
INSTALL_HOOKS = {"pre-install", "post-install"}


def apply_hook_policy(docs, name):
    """What `helm template` emits for Helm hooks, in a world without Helm.

    Hooks that only run on install are ordinary objects now (certificate generation, secret
    initialisation): kept without their hook annotations, Jobs among them with Flux's
    force-recreate annotation (a Job's template is immutable). Hooks that only run on upgrade,
    delete or test (CRD upgrade Jobs, cleanup, helm test) are dropped: Flux owns that lifecycle.
    """
    kept, dropped = [], []
    for d in docs:
        ann = d.get("metadata", {}).get("annotations") or {}
        hook = ann.get("helm.sh/hook")
        if hook is None:
            kept.append(d)
            continue
        events = {e.strip() for e in hook.split(",")}
        if not events & INSTALL_HOOKS:
            dropped.append(f"{d.get('kind')}/{d.get('metadata', {}).get('name')} ({hook})")
            continue
        for a in HOOK_ANNOTATIONS:
            ann.pop(a, None)
        if d.get("kind") == "Job":
            ann["kustomize.toolkit.fluxcd.io/force"] = "enabled"
        if not ann:
            d["metadata"].pop("annotations", None)
        kept.append(d)
    if dropped:
        print(f"{name}: dropped {len(dropped)} upgrade/delete/test hook objects: {', '.join(dropped)}", file=sys.stderr)
    return kept


def load(path):
    if not path.exists():
        return []
    return [d for d in yaml.safe_load_all(path.read_text()) if d]


def patch(docs, patches, workdir):
    """Apply kustomize patches to docs."""
    with tempfile.TemporaryDirectory() as t:
        t = pathlib.Path(t)
        (t / "resources.yaml").write_text(yaml.safe_dump_all(docs, sort_keys=True))
        (t / "kustomization.yaml").write_text(
            yaml.safe_dump({"resources": ["resources.yaml"], "patches": patches}, sort_keys=True)
        )
        out = run(["kustomize", "build", str(t)])
    return [d for d in yaml.safe_load_all(out) if d]


def write(path, docs):
    crds = crd_scopes(docs)

    def key(d):
        m = d.get("metadata", {})
        return (m.get("namespace", ""), d.get("kind", ""), m.get("name", ""))

    docs = sorted(docs, key=key)
    path.write_text("".join("---\n" + yaml.safe_dump(d, sort_keys=True, width=1 << 20) for d in docs))


def main():
    workdir, outdir = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    approx = pathlib.Path(sys.argv[3]) if len(sys.argv) > 3 else None
    meta = json.loads((workdir / "meta.json").read_text())
    outdir.mkdir(parents=True, exist_ok=True)

    plain = load(workdir / "plain.yaml")
    chart_docs = helm_template(meta, workdir) if "chart" in meta else []
    # Variant B has no Helm in the cluster, so hooks need a policy; in variant A helm-controller
    # runs them itself and the approximate render shows them as they are.
    if meta["variant"] != "helmrelease":
        chart_docs = apply_hook_policy(chart_docs, meta["name"])

    if meta["variant"] == "helmrelease":
        published, preview = plain, chart_docs
    else:
        published, preview = chart_docs + plain, None

    patches_file = workdir / "patches.json"
    if meta["hasPatches"]:
        patches = json.loads(patches_file.read_text())
        published = patch(published, patches, workdir)
        if preview:
            preview = patch(preview, patches, workdir)

    # Namespaced objects without a namespace would land in `default` when the Kustomization has
    # no targetNamespace: give them the component's namespace.
    crds = crd_scopes(published + (preview or []))
    ns = meta.get("namespace")
    for docs in (published, preview or []):
        for d in docs:
            m = d.setdefault("metadata", {})
            if ns and "namespace" not in m and not is_cluster_scoped(d, crds):
                m["namespace"] = ns

    write(outdir / "manifests.yaml", published)
    if preview is not None and approx is not None:
        approx.parent.mkdir(parents=True, exist_ok=True)
        write(approx, preview)


main()
