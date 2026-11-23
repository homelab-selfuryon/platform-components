"""Tests for promote.py: python3 -m unittest discover -s scripts -p 'test_*.py'"""

import unittest

import promote

TODAY = "2026-11-23"
PG18 = "18.7-system-trixie@sha256:" + "b" * 64
PG19 = "19.0-system-trixie@sha256:" + "7" * 64


def inp(pins, offered, **kw):
    base = {
        "target": "alpha-01",
        "source": "latest",
        "offered": offered,
        "pins": pins,
        "resolved": list(pins),
        "named": [],
        "excluded": [],
        "allowMajor": False,
        "ignoreHolds": False,
        "holds": {},
    }
    base.update(kw)
    return base


def run(pins, offered, **kw):
    return promote.plan(inp(pins, offered, **kw), TODAY)


class Gates(unittest.TestCase):
    def test_minor_moves(self):
        p = run({"cilium": "1.20.5"}, {"cilium": "1.20.6"})
        self.assertEqual(p.pins, {"cilium": "1.20.6"})
        self.assertEqual(p.skipped, {})

    def test_digest_only_moves(self):
        p = run({"x": "1.0.0@sha256:" + "a" * 64}, {"x": "1.0.0@sha256:" + "c" * 64})
        self.assertIn("x", p.moves)

    def test_major_needs_name_and_allow(self):
        p = run({"postgresql": PG18}, {"postgresql": PG19})
        self.assertEqual(p.pins["postgresql"], PG18)
        self.assertIn("major", p.skipped["postgresql"][2])
        p = run({"postgresql": PG18}, {"postgresql": PG19}, named=["postgresql"])
        self.assertIn("major", p.skipped["postgresql"][2])
        p = run({"postgresql": PG18}, {"postgresql": PG19}, named=["postgresql"], allowMajor=True)
        self.assertEqual(p.pins["postgresql"], PG19)

    def test_zero_major_moves(self):
        self.assertIn("cnpg", run({"cnpg": "0.29.2"}, {"cnpg": "0.30.0"}).moves)

    def test_downgrade_never(self):
        for kw in ({}, {"named": ["x"]}, {"named": ["x"], "allowMajor": True, "ignoreHolds": True}):
            p = run({"x": "v2.10.0"}, {"x": "v2.9.9"}, **kw)
            self.assertIn("downgrade", p.skipped["x"][2], kw)

    def test_padded_core(self):
        self.assertIn("x", run({"x": "1.2"}, {"x": "1.2.1"}).moves)
        self.assertIn("downgrade", run({"x": "1.2.1"}, {"x": "1.2"}).skipped["x"][2])

    def test_suffix_change_needs_name(self):
        p = run({"pg": "18.7-system-trixie"}, {"pg": "18.7-standard-trixie"})
        self.assertIn("suffix", p.skipped["pg"][2])
        self.assertIn("pg", run({"pg": "1.0.0-rc.1"}, {"pg": "1.0.0"}, named=["pg"]).moves)

    def test_unparsed_needs_name(self):
        self.assertIn("not a version", run({"x": "main"}, {"x": "1.0.0"}).skipped["x"][2])
        self.assertIn("x", run({"x": "main"}, {"x": "1.0.0"}, named=["x"]).moves)


class Policy(unittest.TestCase):
    HOLD = {"reason": "waits for a fix", "since": "2026-11-01"}

    def test_hold(self):
        p = run({"x": "1.0.0", "y": "1.0.0"}, {"x": "1.1.0", "y": "1.1.0"}, holds={"x": self.HOLD})
        self.assertIn("held", p.skipped["x"][2])
        self.assertIn("y", p.moves)
        self.assertIn("x", run({"x": "1.0.0"}, {"x": "1.1.0"}, holds={"x": self.HOLD}, ignoreHolds=True).moves)

    def test_hold_lapses(self):
        hold = dict(self.HOLD, until="2026-11-22")
        self.assertIn("x", run({"x": "1.0.0"}, {"x": "1.1.0"}, holds={"x": hold}).moves)
        hold = dict(self.HOLD, until=TODAY)
        self.assertIn("x", run({"x": "1.0.0"}, {"x": "1.1.0"}, holds={"x": hold}).skipped)

    def test_cluster_hold(self):
        p = run({"x": "1.0.0", "y": "1.0.0"}, {"x": "1.1.0", "y": "1.1.0"}, clusterHolds={"x": self.HOLD})
        self.assertIn("held on alpha-01", p.skipped["x"][2])
        self.assertIn("y", p.moves)
        p = run({"x": "1.0.0"}, {"x": "1.1.0"}, clusterHolds={"x": self.HOLD}, ignoreHolds=True)
        self.assertIn("x", p.moves)
        hold = dict(self.HOLD, until="2026-11-22")
        self.assertIn("x", run({"x": "1.0.0"}, {"x": "1.1.0"}, clusterHolds={"x": hold}).moves)

    def test_exclude(self):
        p = run({"x": "1.0.0", "y": "1.0.0"}, {"x": "1.1.0", "y": "1.1.0"}, excluded=["x"])
        self.assertEqual(list(p.moves), ["y"])
        self.assertEqual(p.skipped, {})


class Selection(unittest.TestCase):
    def test_named_adds_and_keeps_order(self):
        p = run({"b": "1.0.0", "a": "1.0.0"}, {"a": "1.1.0", "b": "1.0.0", "c": "2.0.0"}, named=["c", "a"])
        self.assertEqual(list(p.pins.items()), [("b", "1.0.0"), ("a", "1.1.0"), ("c", "2.0.0")])

    def test_unknown_and_missing(self):
        with self.assertRaises(SystemExit):
            run({"x": "1.0.0"}, {"x": "1.0.0"}, named=["typo"])
        with self.assertRaises(SystemExit):
            run({"x": "1.0.0"}, {}, named=["x"])
        with self.assertRaises(SystemExit):
            run({"x": "1.0.0"}, {"x": "2.0.0"}, allowMajor=True)

    def test_describe(self):
        p = run({"postgresql": PG18, "x": "1.0.0"}, {"postgresql": PG19, "x": "1.1.0"})
        latest = {"components": [{"name": "x", "datasource": "docker", "package": "ghcr.io/o/x"}]}
        body = promote.describe(p, inp({}, {}), latest)
        self.assertIn("| `x` | 1.0.0 | 1.1.0 | `ghcr.io/o/x` |", body)
        self.assertIn("### Skipped", body)
        self.assertIn("| `postgresql` | 18.7-system-trixie `bbbbbbbbbbbb` | 19.0-system-trixie `777777777777` |", body)


if __name__ == "__main__":
    unittest.main()
