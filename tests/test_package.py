"""The .mcase package format shared with the Godot game, the bundled library and parity fixtures."""

import copy
import glob
import hashlib
import json
import os
import shutil
import tempfile
import unittest

from mystery.cases.export import snapshot_hook
from mystery.cases.library import run_python
from mystery.cases.package import (FORMAT_VERSION, build_package, read_package, seal, unpack_to_case_dir, unseal,
                                   validate_package)
from mystery.investigate.session import Investigation
from mystery.sim.engine import simulate

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIBRARY = os.path.join(ROOT, "godot", "cases")
PARITY = os.path.join(ROOT, "godot", "tests", "parity")


def library_files():
    return sorted(glob.glob(os.path.join(LIBRARY, "*.mcase")))


class Seal(unittest.TestCase):
    def test_round_trip_and_tamper_detection(self):
        truth = {"answer": {"responsible": "felix"}, "narrative": "Felix did it — at night."}
        sealed = seal(truth, "case-1")
        self.assertNotIn("felix", sealed["data"].lower())
        self.assertEqual(unseal(sealed, "case-1"), truth)
        with self.assertRaises(ValueError):
            unseal(sealed, "case-2")  # the case id is part of the key
        broken = dict(sealed, data=sealed["data"][:-4] + "AAAA")
        with self.assertRaises(ValueError):
            unseal(broken, "case-1")


class Library(unittest.TestCase):
    def test_every_bundled_case_validates_and_its_seal_opens(self):
        files = library_files()
        self.assertGreaterEqual(len(files), 10)
        for path in files:
            with self.subTest(case=os.path.basename(path)):
                pkg = read_package(path)
                self.assertEqual(validate_package(pkg), [])
                truth = unseal(pkg["sealed_truth"], pkg["case_id"])
                self.assertEqual(truth["case_id"], pkg["case_id"])
                self.assertNotIn(truth["narrative"], json.dumps(pkg["investigation"]))

    def test_index_matches_files_and_holds_no_spoilers(self):
        with open(os.path.join(LIBRARY, "index.json"), encoding="utf-8") as f:
            index = json.load(f)
        self.assertEqual(sorted(e["file"] for e in index["cases"]), [os.path.basename(p) for p in library_files()])
        for e in index["cases"]:
            with open(os.path.join(LIBRARY, e["file"]), "rb") as f:
                self.assertEqual(hashlib.sha256(f.read()).hexdigest(), e["sha256"])
            self.assertEqual(set(e), {"file", "case_id", "title", "town", "start_label", "season", "difficulty",
                                      "sha256"})

    def test_a_bundled_case_regenerates_identically_from_its_seed(self):
        pkg = read_package(library_files()[0])
        g = pkg["generator"]
        hook, store = snapshot_hook(selected=g["incident"])
        simulate(g["seed"], g["days"], g["profile"], g["residents"], case_hook=hook)
        again = build_package(store[g["incident"]])
        self.assertEqual(again["generator"]["event_log_digest"], g["event_log_digest"])
        self.assertEqual(again, pkg)

    def test_residents_can_be_found_where_the_simulation_left_them(self):
        """now_at is present state at the frozen instant, observable in town, and always a real place."""
        for path in library_files():
            inv = read_package(path)["investigation"]
            places = {p["id"] for p in inv["places"]}
            with self.subTest(case=inv["case_id"]):
                for r in inv["residents"]:
                    if r["condition"] == "deceased":
                        self.assertIsNone(r["now_at"])
                    else:
                        self.assertIn(r["now_at"], places)

    def test_packages_without_whereabouts_still_validate(self):
        """Schema 0.1 packages (no now_at) stay readable."""
        pkg = read_package(library_files()[0])
        for r in pkg["investigation"]["residents"]:
            r.pop("now_at")
        self.assertEqual(validate_package(pkg), [])

    def test_unpacked_package_plays_in_python(self):
        with tempfile.TemporaryDirectory() as tmp:
            case_dir = unpack_to_case_dir(read_package(library_files()[0]), tmp)
            inv = Investigation(case_dir, fresh=True)
            inv.surrender()
            self.assertTrue(any("THE TRUTH" in line for line in inv.reveal()))


class Validation(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pkg = read_package(library_files()[0])

    def broken(self, mutate):
        pkg = copy.deepcopy(self.pkg)
        mutate(pkg)
        return validate_package(pkg)

    def test_rejections(self):
        first_items = lambda p: next(iter(p["investigation"]["testimony"].values()))["items"]  # noqa: E731
        cases = {
            "wrong format": lambda p: p.update(format="something-else"),
            "future version": lambda p: p.update(format_version=FORMAT_VERSION + 1),
            "truth field leaked": lambda p: first_items(p)[0].update(lie=True),
            "event id leaked": lambda p: first_items(p)[0].update(text="see E000123"),
            "missing field": lambda p: p["investigation"]["hook"].pop("window"),
            "unknown topic": lambda p: first_items(p)[0]["topics"].append("secrets"),
            "unknown resident": lambda p: first_items(p)[0]["about"].append("nobody"),
            "corrupted seal": lambda p: p["sealed_truth"].update(data="AAAA" + p["sealed_truth"]["data"][4:]),
            "bad fact": lambda p: first_items(p)[0]["facts"].append({"who": "x", "place": "y", "from": 2, "to": 1}),
            "bad style": lambda p: next(iter(p["investigation"]["testimony"].values())).update(style="shifty"),
            "unknown whereabouts": lambda p: p["investigation"]["residents"][0].update(now_at="atlantis"),
        }
        for name, mutate in cases.items():
            with self.subTest(name):
                self.assertTrue(self.broken(mutate), f"{name} was not rejected")


class Parity(unittest.TestCase):
    """The fixtures Godot replays must still be what the Python rules produce today."""

    def test_fixtures_match_current_python_rules(self):
        fixtures = sorted(glob.glob(os.path.join(PARITY, "*.json")))
        self.assertGreaterEqual(len(fixtures), 4)
        families = set()
        for path in fixtures:
            with open(path, encoding="utf-8") as f:
                fx = json.load(f)
            pkg = read_package(os.path.join(LIBRARY, fx["case_file"]))
            families.add(unseal(pkg["sealed_truth"], pkg["case_id"])["incident"]["family"])
            tmp = tempfile.mkdtemp()
            try:
                case_dir = unpack_to_case_dir(pkg, tmp)
                for script in fx["scripts"]:
                    with self.subTest(case=fx["case_file"], script=script["name"]):
                        self.assertEqual(run_python(case_dir, script["actions"]), script["expected"])
            finally:
                shutil.rmtree(tmp)
        self.assertEqual(families, {"theft", "accounting_error", "assault", "collision", "fall"})

    def test_fixtures_exercise_sealing_and_conflicts(self):
        path = sorted(glob.glob(os.path.join(PARITY, "*.json")))[0]
        with open(path, encoding="utf-8") as f:
            script = json.load(f)["scripts"][0]
        ops = [r["op"] for r in script["expected"]]
        self.assertEqual(script["expected"][0], {"op": "reveal", "sealed": True, "model": None})
        self.assertIn("timeline", ops)
        self.assertEqual(script["expected"][-1]["error"], "closed")


if __name__ == "__main__":
    unittest.main()
