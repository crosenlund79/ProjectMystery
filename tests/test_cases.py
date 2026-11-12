"""Acceptance: testimony is grounded, cases can end in accident / no crime / unresolved,
a case can be played from start to theory to reveal, and batches distinguish run types."""

import os
import tempfile
import unittest

from mystery.cases.export import write_case
from mystery.diagnostics.batch import run_batch
from mystery.investigate.repl import run_script
from mystery.investigate.session import Investigation
from tests.helpers import find_case, run_with_cases


class Testimony(unittest.TestCase):
    def test_truthful_statements_trace_to_perception_or_named_sources(self):
        _, _, case = find_case("normal", family="theft")
        audit = case["truth"]["testimony_audit"]
        for rid, t in case["investigation"]["testimony"].items():
            for it in t["items"]:
                a = audit[it["key"]]
                if a.get("summary"):
                    # a summary traces through the statements it stands for, each with its own belief
                    self.assertEqual(a["members"], it["members"])
                    for m in it["members"]:
                        self.assertIsNotNone(audit[m]["belief"])
                    continue
                if a["status"] == "lie":
                    self.assertTrue(a["error"])
                    continue
                if "whereabouts" in it["topics"] and a["belief"] is None:
                    continue  # their own movements
                self.assertIsNotNone(a["belief"])
                self.assertEqual(a["source"], it["source"])
                if it["source"] == "told":
                    self.assertIn("told me", it["text"])
                if it["source"] == "saw":
                    # "I saw Ana at the pub", or for a state of affairs seen to be true, "I know Ana owes ..."
                    self.assertTrue(it["text"].startswith(("I saw", "I know")))

    def test_culprit_lies_about_their_whereabouts(self):
        _, _, case = find_case("normal", family="theft")
        culprit = case["truth"]["answer"]["responsible"]
        lies = [a for a in case["truth"]["testimony_audit"].values() if a.get("lie") and a["speaker"] == culprit]
        self.assertTrue(lies)


class Outcomes(unittest.TestCase):
    def test_no_crime_case_exists(self):
        _, _, case = find_case("normal", family="accounting_error", verdicts=None)
        self.assertEqual(case["truth"]["answer"]["outcome"], "no_crime")
        self.assertIsNone(case["truth"]["answer"]["responsible"])

    def test_accident_case_exists(self):
        _, _, case = find_case("tension", outcome="accident", verdicts=None, seeds=range(1, 60))
        self.assertIn(case["truth"]["answer"]["mechanism"], ("accidental_fall", "struck_by_vehicle",
                                                             "vehicle_collision"))

    def test_unresolved_is_a_legitimate_answer(self):
        _, _, case = find_case("normal", family="theft", verdicts=("unsolvable", "ambiguous"))
        with tempfile.TemporaryDirectory() as tmp:
            inv = Investigation(write_case(case, tmp), fresh=True)
            inv.submit("unresolved", None)
            inv.reveal()
            self.assertGreaterEqual(inv.state["score"]["total"], 50)


class EndToEnd(unittest.TestCase):
    def test_investigate_submit_reveal(self):
        seed, iid, case = find_case("normal", family="theft")
        culprit = case["truth"]["answer"]["responsible"]
        name = case["truth"]["private_states"][culprit]["name"].split()[0]
        people = [r["first"] for r in case["investigation"]["residents"] if r["condition"] != "deceased"]
        script = ["help", "people", "places", "vehicles", f"inspect {case['investigation']['hook']['place']}"]
        for p in people:
            script += [f"ask {p} whereabouts", f"ask {p} window", f"ask {p} window press"]
        script += ["read ledger", "notebook", "timeline", "hint", "note the lock was forced",
                   "submit", "1", name, "1", "S1", "They took it.", "reveal", "quit"]
        with tempfile.TemporaryDirectory() as tmp:
            path = write_case(case, tmp)
            out = "\n".join(run_script(path, script))
            self.assertIn("THE TRUTH", out)
            self.assertIn("SCORE:", out)
            self.assertIn("WHAT ACTUALLY HAPPENED", out)
            inv = Investigation(path)
            self.assertTrue(inv.state["revealed"])
            self.assertGreaterEqual(inv.state["score"]["total"], 60)
            self.assertTrue(os.path.exists(os.path.join(path, "session.json")))


class Batch(unittest.TestCase):
    def test_batch_report_distinguishes_runs_and_cases(self):
        rep = run_batch(runs=4, days=30, profile="scarcity", start_seed=1)
        for key in ("runs_without_incident", "runs_with_major_incident", "candidate_cases", "suitable_cases",
                    "case_verdicts", "deescalated", "integrity_failures", "runtime_per_100_days_s"):
            self.assertIn(key, rep)
        self.assertEqual(rep["runs_with_integrity_failures"], [])
        self.assertLessEqual(rep["suitable_cases"], rep["candidate_cases"])

    def test_cases_are_frozen_at_case_start(self):
        sim, store = run_with_cases(3)
        for case in store.values():
            start = case["truth"]["case_start"]
            self.assertTrue(all(ev["time"] <= start for ev in case["truth"]["chain"]))


if __name__ == "__main__":
    unittest.main()
