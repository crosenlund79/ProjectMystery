"""Acceptance: the player's view cannot reach the sealed objective log during an investigation."""

import builtins
import os
import shutil
import tempfile
import unittest
from unittest import mock

from mystery.cases.export import write_case
from mystery.diagnostics.integrity import check_case, check_spoiler_boundary
from mystery.investigate.session import Investigation, InvestigationError
from tests.helpers import find_case


class SpoilerBoundary(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.seed, cls.iid, cls.case = find_case("normal", family="theft")
        cls.tmp = tempfile.mkdtemp()
        cls.path = write_case(cls.case, cls.tmp)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp)

    def test_investigation_view_has_no_truth(self):
        self.assertEqual(check_spoiler_boundary(self.case["investigation"]), [])
        self.assertEqual(check_case(self.case), [])

    def test_play_never_opens_truth(self):
        opened = []
        real_open = builtins.open

        def spy(file, *a, **kw):
            opened.append(os.path.basename(str(file)))
            return real_open(file, *a, **kw)

        with mock.patch("builtins.open", spy):
            inv = Investigation(self.path, fresh=True)
            someone = inv.data["residents"][0]["first"]
            for topic in ("whereabouts", "window", "incident", "money", "rumors"):
                inv.ask(someone, topic)
                inv.ask(someone, topic, press=True)
            for p in inv.data["places"]:
                inv.inspect(p["id"])
            for book in inv.data["records"]:
                inv.read(book)
            inv.buy_hint()
            inv.timeline()
            inv.save()
            self.assertIn("The truth stays sealed", inv.reveal()[0])
        self.assertNotIn("truth.json", opened)

    def test_works_without_truth_file_and_reveal_is_gated(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = shutil.copytree(self.path, os.path.join(tmp, "case"))
            os.remove(os.path.join(path, "truth.json"))
            inv = Investigation(path, fresh=True)
            inv.ask(inv.data["residents"][1]["first"], "window")
            inv.submit("unresolved", None)
            with self.assertRaises(FileNotFoundError):
                inv.reveal()  # only now does it reach for the sealed file

    def test_reveal_is_irreversible(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = shutil.copytree(self.path, os.path.join(tmp, "case"))
            inv = Investigation(path, fresh=True)
            inv.surrender()
            self.assertTrue(any("THE TRUTH" in line for line in inv.reveal()))
            with self.assertRaises(InvestigationError):
                inv.ask(inv.data["residents"][0]["first"], "window")
            again = Investigation(path)
            with self.assertRaises(InvestigationError):
                again.inspect("square")


if __name__ == "__main__":
    unittest.main()
