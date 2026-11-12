"""How people answer (mystery/cases/export.py summaries and eras, mystery/investigate/dialogue.py).

Checked on every bundled case: first answers are short; everyday matters are told in summary and the
statements behind each summary are kept word for word and told on "tell me more"; older matters come up on
"and before that?"; and nothing anyone is willing to say is lost - every statement can still be heard.
"""

import glob
import os
import statistics
import tempfile
import unittest

from mystery.cases.package import read_package, unseal
from mystery.investigate import dialogue
from mystery.investigate.dialogue import BASE_TOPICS

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIBRARY = os.path.join(ROOT, "godot", "cases")
BASE = [t for t, _ in BASE_TOPICS]


def bundled():
    for path in sorted(glob.glob(os.path.join(LIBRARY, "*.mcase"))):
        pkg = read_package(path)
        yield pkg, unseal(pkg["sealed_truth"], pkg["case_id"])


def alive(inv):
    return [r["id"] for r in inv["residents"] if r["condition"] != "deceased"]


def heard(state, rid, topic, press=False, follow=""):
    lines, shown = dialogue.answer(state["inv"], state, rid, topic, press, follow)
    for it in shown:
        state["by_ref"][it["key"]] = it["key"]
    return lines, shown, dialogue.follow_ups(state["inv"], state, rid, topic)


def fresh(inv):
    return {"inv": inv, "by_ref": {}}


class Conversation(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cases = list(bundled())

    def test_first_answers_are_short(self):
        counts = []
        for pkg, _truth in self.cases:
            inv = pkg["investigation"]
            for rid in alive(inv):
                for topic in BASE:
                    lines, _, _ = heard(fresh(inv), rid, topic)
                    n = len([text for text, items in lines if items])
                    counts.append(n)
                    self.assertLessEqual(n, 15, f"{pkg['case_id']} {rid} {topic}: {n} lines at the first ask")
        self.assertLessEqual(statistics.mean(counts), 3.0)

    def test_nothing_anyone_would_say_is_lost(self):
        """Every statement can still be heard: by asking, pressing, going back and asking for more, on the
        base topics and about each person."""
        for pkg, _truth in self.cases:
            inv = pkg["investigation"]
            for rid in alive(inv):
                st = fresh(inv)
                st["goodwill"] = {rid: 99}
                topics = sorted({tp for it in inv["testimony"][rid]["items"] for tp in it["topics"]})
                for topic in topics:
                    heard(st, rid, topic, press=True)
                    heard(st, rid, topic, follow="earlier")
                    heard(st, rid, topic, follow="more")
                keys = {it["key"] for it in inv["testimony"][rid]["items"]}
                self.assertEqual(keys - set(st["by_ref"]), set(), f"{pkg['case_id']} {rid}: never told")

    def test_summaries_stand_for_their_members(self):
        for pkg, truth in self.cases:
            inv, audit = pkg["investigation"], truth["testimony_audit"]
            first = {r["id"]: r["first"] for r in inv["residents"]}
            for rid, t in inv["testimony"].items():
                by_key = {it["key"]: it for it in t["items"]}
                for it in t["items"]:
                    if not audit[it["key"]].get("summary"):
                        continue
                    members = [by_key[m] for m in it["members"]]
                    self.assertGreaterEqual(len(members), 2)
                    for m in members:
                        self.assertEqual(m["in"], it["key"])
                        self.assertFalse(m["guarded"], "a guarded statement was summed up")
                        self.assertFalse(audit[m["key"]].get("lie"), "a lie was summed up")
                        self.assertNotIn("dark", m["text"], "a sighting in the dark was summed up")
                        for f in m["facts"]:
                            self.assertIn(f, it["facts"], "the timeline would lose a member's claim")
                        for who in m["about"]:
                            if who != rid:
                                self.assertIn(first[who], it["text"], f"{it['text']!r} leaves out {first[who]}")
                    self.assertEqual(it.get("era", "recent"), members[0].get("era", "recent"))
                    statuses = {audit[m["key"]]["status"] for m in members}
                    self.assertEqual(audit[it["key"]]["status"] == "mistaken", "mistaken" in statuses)

    def test_tell_me_more_tells_only_what_is_new(self):
        tried = 0
        for pkg, _truth in self.cases:
            inv = pkg["investigation"]
            for rid in alive(inv):
                st = fresh(inv)
                _, shown, offer = heard(st, rid, "money")
                summaries = [it for it in shown if it.get("members")]
                if not summaries:
                    continue
                self.assertTrue(offer["can_more"])
                lines, more, offer = heard(st, rid, "money", follow="more")
                self.assertEqual({it["key"] for it in more}, {m for s in summaries for m in s["members"]})
                self.assertFalse(offer["can_more"])
                lines, again, _ = heard(st, rid, "money", follow="more")
                self.assertEqual(again, [])
                self.assertEqual(lines, [(dialogue.NOTHING_MORE, [])])
                tried += 1
        self.assertGreater(tried, 10)

    def test_and_before_that_goes_back_in_time(self):
        tried = 0
        for pkg, _truth in self.cases:
            inv = pkg["investigation"]
            boundary = inv["hook"]["recent_from"]
            self.assertLessEqual(boundary, inv["hook"]["window"][0])
            for rid in alive(inv):
                for it in inv["testimony"][rid]["items"]:
                    self.assertFalse(it.get("era") == "earlier" and "window" in it["topics"])
                    if it.get("era") == "earlier" and it["time"] is not None:
                        self.assertLess(it["time"], boundary)
                st = fresh(inv)
                _, first, offer = heard(st, rid, "money")
                self.assertFalse([it for it in first if it.get("era") == "earlier"])
                if not offer["can_earlier"]:
                    continue
                _, back, offer = heard(st, rid, "money", follow="earlier")
                self.assertTrue(back)
                self.assertTrue(all(it.get("era") == "earlier" for it in back))
                self.assertFalse(offer["can_earlier"])
                tried += 1
        self.assertGreater(tried, 10)

    def test_the_plain_account_and_the_exact_one_agree(self):
        """Asked where they were, people say where they spent their time; asked to be exact, every move.
        Both tell the same story - true or false."""
        for pkg, truth in self.cases:
            inv, audit = pkg["investigation"], truth["testimony_audit"]
            for rid in alive(inv):
                items = {it["key"]: it for it in inv["testimony"][rid]["items"]}
                plains = [it for it in items.values() if "segments" in audit[it["key"]] and "in" not in it]
                for plain in plains:
                    exact = items[plain["members"][0]]
                    self.assertEqual(audit[plain["key"]]["status"], audit[exact["key"]]["status"])
                    self.assertLessEqual(len(plain["text"]), len(exact["text"]))
                    for f in exact["facts"]:
                        inside = any(g["place"] == f["place"] and g["from"] <= f["from"] and f["to"] <= g["to"]
                                     for g in plain["facts"])
                        self.assertTrue(inside or f["to"] - f["from"] < 25,
                                        f"{pkg['case_id']} {rid}: the plain account drops {f}")

    def test_the_text_game_offers_the_follow_ups(self):
        from mystery.cases.package import unpack_to_case_dir
        from mystery.investigate.session import Investigation
        pkg, _truth = self.cases[0]
        with tempfile.TemporaryDirectory() as tmp:
            case_dir = unpack_to_case_dir(pkg, tmp)
            inv = Investigation(case_dir, session_path=os.path.join(tmp, "s.json"), fresh=True)
            rid = alive(pkg["investigation"])[0]
            res = inv.ask_result(rid, "whereabouts")
            self.assertTrue(res["can_more"], "the plain account should offer the exact one")
            more = inv.ask_result(rid, "whereabouts", follow="more")
            self.assertEqual(len(more["lines"]), 1)
            self.assertFalse(more["can_more"])


if __name__ == "__main__":
    unittest.main()
