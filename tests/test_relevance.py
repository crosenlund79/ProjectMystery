"""Evidence relevance (mystery/cases/relevance.py) and the money provenance behind it.

Checked on every bundled case: verdicts come from the causal record, never depend on whether a statement
is true, judge where-and-when information by place and time only, travel in the package sealed one by
one, and never show up in the player-safe view.
"""

import collections
import glob
import json
import os
import unittest

from mystery.cases.package import (REL_SCHEME, REL_VALUES, read_package, seal_item, unseal, unseal_item,
                                   validate_package)
from mystery.cases.relevance import MARGIN, VERDICTS, WHERE_KINDS
from mystery.sim.engine import simulate

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIBRARY = os.path.join(ROOT, "godot", "cases")


def bundled():
    for path in sorted(glob.glob(os.path.join(LIBRARY, "*.mcase"))):
        pkg = read_package(path)
        yield pkg, unseal(pkg["sealed_truth"], pkg["case_id"])


def statements(pkg):
    return {it["key"]: it for t in pkg["investigation"]["testimony"].values() for it in t["items"]}


class Relevance(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cases = list(bundled())

    def test_every_item_has_a_verdict_that_opens_from_the_package(self):
        for pkg, truth in self.cases:
            with self.subTest(case=pkg["case_id"]):
                rel = truth["relevance"]
                items = pkg["relevance"]["items"]
                self.assertEqual(pkg["relevance"]["scheme"], REL_SCHEME)
                inv = pkg["investigation"]
                refs = set(statements(pkg))
                refs |= {tr["id"] for p in inv["places"] for tr in p["traces"]}
                refs |= {tr["id"] for v in inv["vehicles"] for tr in v["traces"]}
                refs |= {x["id"] for b in inv["records"].values() for x in b["entries"]}
                self.assertTrue(refs <= set(items), "an item the player can find has no verdict")
                for ref, v in rel.items():
                    self.assertIn(v["verdict"], VERDICTS)
                    self.assertEqual(unseal_item(items[ref], pkg["case_id"], ref), f"{v['verdict']}|{v['reason']}")

    def test_verdicts_are_not_in_the_player_view(self):
        for pkg, truth in self.cases:
            text = json.dumps(pkg["investigation"])
            for word in ("relevance", "connected", "unrelated", "where_when"):
                self.assertNotIn(f'"{word}', text)

    def test_each_case_has_connected_and_unrelated_information(self):
        for pkg, truth in self.cases:
            with self.subTest(case=pkg["case_id"]):
                verdicts = collections.Counter(v["verdict"] for v in truth["relevance"].values())
                self.assertGreater(verdicts["connected"], 0)
                self.assertGreater(verdicts["unrelated"], verdicts["connected"])

    def test_connected_means_it_stems_from_the_causal_web(self):
        for pkg, truth in self.cases:
            web = set(truth["relevance_web"])
            chain = {c["id"] for c in truth["chain"]}
            self.assertTrue(chain <= web)
            for ref, v in truth["relevance"].items():
                if v["verdict"] == "connected":
                    self.assertIn(v["source"], web, f"{pkg['case_id']} {ref}")
                elif v["reason"] == "outside" and v["source"] is not None:
                    self.assertNotIn(v["source"], web, f"{pkg['case_id']} {ref}")

    def test_physical_evidence_and_records_follow_what_made_them(self):
        for pkg, truth in self.cases:
            web = set(truth["relevance_web"])
            for ref, a in truth["evidence_audit"].items():
                self.assertEqual(truth["relevance"][ref]["verdict"],
                                 "connected" if a["created_by"] in web else "unrelated")
            for ref, a in truth["record_audit"].items():
                self.assertEqual(truth["relevance"][ref]["verdict"],
                                 "connected" if a["event"] in web else "unrelated")

    def test_where_and_when_information_is_judged_by_place_and_time_only(self):
        """Re-derive every where-and-when verdict from the claimed place and time and the incident's
        footprint alone - no names, no truth."""
        for pkg, truth in self.cases:
            marks = [tuple(m) for m in truth["relevance_footprint"]]
            items = statements(pkg)
            for ref, v in truth["relevance"].items():
                if v["kind"] not in WHERE_KINDS and v["kind"] != "account":
                    continue
                it = items[ref]
                facts = [(f["place"], f["from"], f["to"]) for f in it["facts"]] or \
                    ([(it["place"], it["time"], it["time"])] if it["place"] and it["time"] is not None else [])
                touches = any(p == w and s - MARGIN <= t <= e + MARGIN for p, s, e in facts for w, t in marks)
                self.assertEqual(v["verdict"], "uncertain" if touches else "unrelated", f"{pkg['case_id']} {ref}")
                self.assertIsNone(v["source"])

    def test_verdicts_never_depend_on_whether_a_statement_is_true(self):
        """Statements stemming from the same event get the same verdict whether accurate, mistaken or a
        lie; and lies are spread across verdicts like everything else rather than standing out."""
        lies = collections.Counter()
        for pkg, truth in self.cases:
            by_source = collections.defaultdict(set)
            audit = truth["testimony_audit"]
            for ref, v in truth["relevance"].items():
                if ref in audit and v["source"]:
                    by_source[v["source"]].add((v["verdict"], audit[ref]["status"]))
                if ref in audit and audit[ref]["status"] == "lie":
                    lies[v["verdict"]] += 1
            for source, seen in by_source.items():
                self.assertEqual(len({verdict for verdict, _ in seen}), 1, f"{pkg['case_id']} {source}: {seen}")
        self.assertGreater(sum(lies.values()), 0, "no lies in the library to check")

    def test_the_responsible_persons_own_account_is_judged_like_anyone_elses(self):
        """A culprit's false account of where they were is never 'connected': it is where-and-when
        information, judged by what it claims, exactly like every innocent account."""
        for pkg, truth in self.cases:
            audit = truth["testimony_audit"]
            for ref, a in audit.items():
                if "segments" in a and ref in truth["relevance"]:
                    self.assertNotEqual(truth["relevance"][ref]["verdict"], "connected")

    def test_validation_rejects_tampered_relevance(self):
        pkg, _truth = self.cases[0]
        bad = json.loads(json.dumps(pkg))
        ref = next(iter(bad["relevance"]["items"]))
        bad["relevance"]["items"][ref] = seal_item("nonsense", "another-case", ref)
        self.assertTrue(validate_package(bad))
        bad = json.loads(json.dumps(pkg))
        bad.pop("relevance")
        self.assertEqual(validate_package(bad), [], "packages without relevance must stay readable")

    def test_sealed_values_are_one_length(self):
        lengths = {len(seal_item(v, "case", "K0001")) for v in REL_VALUES}
        self.assertEqual(len(lengths), 1, "a verdict's length would give it away")


class MoneyProvenance(unittest.TestCase):
    """Spending stolen money is causally linked to the theft, and the bookkeeping changes nothing else."""

    @classmethod
    def setUpClass(cls):
        cls.sim = simulate(7, 60, "normal")

    def test_spending_from_a_stash_is_linked_to_the_withdrawal(self):
        sim = self.sim
        withdrawals = {e.id: e for e in sim.log.events if e.kind == "stash_withdraw"}
        self.assertTrue(withdrawals, "this run has no stash withdrawals to check")
        linked = 0
        for ev in sim.log.events:
            for c in ev.causes:
                if c in withdrawals:
                    w = withdrawals[c]
                    self.assertEqual(ev.actors[:1], w.actors[:1], "someone else's spending was linked")
                    self.assertGreaterEqual(ev.time, w.time)
                    linked += 1
        self.assertGreater(linked, 0, "no spending of stolen money was linked")

    def test_linked_spending_belongs_to_the_theft(self):
        sim = self.sim
        for w in [e for e in sim.log.events if e.kind == "stash_withdraw"]:
            theft = w.causes[0]
            spent = [e.id for e in sim.log.events if w.id in e.causes]
            later = sim.log.consequences(theft, sim.log.events[-1].time)
            for eid in spent:
                self.assertIn(eid, later)


if __name__ == "__main__":
    unittest.main()
