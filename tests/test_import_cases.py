"""The ten import-test cases (import-test-cases/): valid, standalone, varied, and not part of the game."""

import glob
import json
import os
import unittest

from mystery.cases.package import read_package, unseal, validate_package

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FOLDER = os.path.join(ROOT, "import-test-cases")


class ImportTestCases(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.files = sorted(glob.glob(os.path.join(FOLDER, "*.mcase")))
        cls.packages = [read_package(p) for p in cls.files]

    def test_ten_valid_cases(self):
        self.assertEqual(len(self.files), 10)
        for pkg in self.packages:
            with self.subTest(case=pkg["case_id"]):
                self.assertEqual(validate_package(pkg), [])

    def test_not_part_of_the_game(self):
        with open(os.path.join(ROOT, "godot", "cases", "index.json"), encoding="utf-8") as f:
            bundled = {c["case_id"] for c in json.load(f)["cases"]}
        bundled_files = {os.path.basename(p) for p in glob.glob(os.path.join(ROOT, "godot", "cases", "*.mcase"))}
        for pkg, path in zip(self.packages, self.files):
            self.assertNotIn(pkg["case_id"], bundled)
            self.assertNotIn(os.path.basename(path), bundled_files)
        for source in glob.glob(os.path.join(ROOT, "godot", "scripts", "**", "*.gd"), recursive=True):
            with open(source, encoding="utf-8") as f:
                self.assertNotIn("import-test-cases", f.read(), f"{source} refers to the import-test cases")

    def test_varied_and_solvable_from_evidence(self):
        families, seasons, difficulties = set(), set(), set()
        for pkg in self.packages:
            truth = unseal(pkg["sealed_truth"], pkg["case_id"])
            suit = truth["suitability"]
            families.add(suit["family"])
            seasons.add(pkg["summary"]["season"])
            difficulties.add(pkg["summary"]["difficulty"])
            self.assertTrue(suit["solvable_by_evidence"], pkg["case_id"])
        self.assertGreaterEqual(len(families), 4)
        self.assertEqual(len(seasons), 4)
        self.assertGreaterEqual(len(difficulties), 2)

    def test_validation_report_passed(self):
        with open(os.path.join(FOLDER, "VALIDATION.md"), encoding="utf-8") as f:
            report = f.read()
        self.assertIn("all checks passed", report)
        for pkg in self.packages:
            truth = unseal(pkg["sealed_truth"], pkg["case_id"])
            responsible = truth["answer"]["responsible"]
            if responsible:
                name = truth["private_states"][responsible]["name"]
                self.assertNotIn(name, report, "the report gives away who did it")


if __name__ == "__main__":
    unittest.main()
