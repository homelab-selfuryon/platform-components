#!/usr/bin/env python3
"""Inputs for scripts/kyverno-check.sh: which policies, objects and CRDs each run gets.

Usage: kyverno_inputs.py out/<cluster> <all-crds.yaml> <workdir>

`kyverno apply` costs roughly (objects x CRD schema size): it handles every CRD it was given for
every object. So each run gets only what its policies can look at:

  workdir/static/        policies that judge the object alone, over every object they match
                         (component manifests, approximate renders, the sets' Flux Kustomizations)
  workdir/admission/     policies that judge who sends the object (request.userInfo); one run per
                         non-privileged component, as its Flux ServiceAccount component-<name>
    <component>/         resources.yaml, crds.yaml, userinfo.yaml

Objects of kinds no policy matches are left out; the kinds left out are printed, so nothing
disappears silently. CRDs: only the ones of the kinds an object of the run has.
"""
import json
import pathlib
import sys

import yaml

POLICY_KINDS = {"ValidatingPolicy", "ImageValidatingPolicy", "GeneratingPolicy", "DeletingPolicy", "MutatingPolicy"}


def load(path):
    return [d for d in yaml.safe_load_all(path.read_text()) if d] if path.exists() else []


def dump(path, docs):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join("---\n" + yaml.safe_dump(d, sort_keys=False, width=1 << 20) for d in docs))


def group(doc):
    api = doc.get("apiVersion", "")
    return api.split("/")[0] if "/" in api else ""


def plural(kind, crd_plurals):
    """Resource name of a kind: from its CRD, else the usual English rules of the built-in kinds."""
    if kind in crd_plurals:
        return crd_plurals[kind]
    k = kind.lower()
    if k == "endpoints":
        return k
    if k.endswith("y") and k[-2:-1] not in "aeiou":
        return k[:-1] + "ies"
    if k.endswith(("s", "x", "ch", "sh")):
        return k + "es"
    return k + "s"


def rules(policy):
    """(apiGroups, resources) pairs a policy matches; None when it has no resource rules."""
    mc = policy.get("spec", {}).get("matchConstraints")
    if not mc or not mc.get("resourceRules"):
        return None
    out = []
    for r in mc["resourceRules"]:
        res = {x for x in r.get("resources", []) if "/" not in x or x == "*/*"}
        out.append((set(r.get("apiGroups", ["*"])), {"*" if x == "*/*" else x for x in res}))
    return out


def matches(doc, policy_rules, crd_plurals):
    g, p = group(doc), plural(doc.get("kind", ""), crd_plurals)
    for rs in policy_rules:
        if rs is None:
            return True
        for groups, resources in rs:
            if ("*" in groups or g in groups) and ("*" in resources or p in resources):
                return True
    return False


def crds_for(docs, all_crds):
    kinds = {(group(d), d.get("kind")) for d in docs}
    return [c for c in all_crds if (c["spec"]["group"], c["spec"]["names"]["kind"]) in kinds]


def userinfo(sa):
    return {
        "apiVersion": "cli.kyverno.io/v1alpha1",
        "kind": "UserInfo",
        "metadata": {"name": sa},
        "clusterRoles": [],
        "roles": [],
        "userInfo": {
            "username": f"system:serviceaccount:flux-system:{sa}",
            "groups": ["system:serviceaccounts", "system:serviceaccounts:flux-system", "system:authenticated"],
        },
    }


def main():
    base, crd_file, work = (pathlib.Path(a) for a in sys.argv[1:4])
    policies_file = base / "policy" / "components" / "kyverno-policies" / "manifests.yaml"
    policies = [d for d in load(policies_file) if d.get("kind") in POLICY_KINDS]
    admission = [p for p in policies if "request.userInfo" in json.dumps(p)]
    static = [p for p in policies if p not in admission]

    all_crds = [d for d in load(crd_file) if d.get("kind") == "CustomResourceDefinition"]
    crd_plurals = {c["spec"]["names"]["kind"]: c["spec"]["names"]["plural"] for c in all_crds}

    # component name -> (meta, objects); plus the Flux Kustomizations of each set
    components = {}
    for m in sorted((base / ".work").glob("*/*/meta.json")):
        meta = json.loads(m.read_text())
        s, n = meta["set"], meta["name"]
        docs = load(base / s / "components" / n / "manifests.yaml") + load(base / ".approx" / s / f"{n}.yaml")
        components[n] = (meta, [d for d in docs if d.get("kind") != "CustomResourceDefinition"])
    flux = [d for f in sorted(base.glob("*/flux/kustomizations.yaml")) for d in load(f)]

    static_rules = [rules(p) for p in static]
    admission_rules = [rules(p) for p in admission]
    dropped = {}

    def keep(docs, rs):
        kept = []
        for d in docs:
            if matches(d, rs, crd_plurals):
                kept.append(d)
            else:
                k = f"{group(d) or 'core'}/{d.get('kind')}"
                dropped[k] = dropped.get(k, 0) + 1
        return kept

    # Static run: one resource file per component (a single file with duplicates makes the CLI panic).
    st = work / "static"
    dump(st / "policies.yaml", static)
    static_docs = []
    for n, (_, docs) in components.items():
        kept = keep(docs, static_rules)
        if kept:
            dump(st / "resources" / f"{n}.yaml", kept)
            static_docs += kept
    kept = keep(flux, static_rules)
    if kept:
        dump(st / "resources" / "flux-kustomizations.yaml", kept)
        static_docs += kept
    dump(st / "crds.yaml", crds_for(static_docs, all_crds))

    # Admission runs: per non-privileged component, as its ServiceAccount.
    ad = work / "admission"
    dump(ad / "policies.yaml", admission)
    runs = []
    for n, (meta, docs) in components.items():
        if meta.get("privileged"):
            continue
        kept = [d for d in docs if matches(d, admission_rules, crd_plurals)]
        if not kept:
            continue
        dump(ad / n / "resources.yaml", kept)
        dump(ad / n / "crds.yaml", crds_for(kept, all_crds))
        dump(ad / n / "userinfo.yaml", [userinfo(f"component-{n}")])
        runs.append(n)

    print(
        f"static: {len(static)} policies, {len(static_docs)} objects; "
        f"admission: {len(admission)} policies, {len(runs)} components ({', '.join(runs)})",
        file=sys.stderr,
    )
    if dropped:
        print("not matched by any static policy: " + ", ".join(f"{k} x{v}" for k, v in sorted(dropped.items())), file=sys.stderr)


main()
