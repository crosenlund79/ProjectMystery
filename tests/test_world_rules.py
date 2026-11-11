"""Acceptance: the world obeys its own rules in every profile.

* No resident is at two incompatible places at the same time.
* No resident spends money or goods they do not have.
* Every belief is traceable to perception, participation, a named teller or premises.
* Evidence and records exist only because a world event created them.
* Memory can be wrong without the objective history changing.
"""

import unittest

from mystery.diagnostics.integrity import check_simulation
from mystery.sim.engine import SimulationError, simulate

PROFILES = ("normal", "scarcity", "crisis", "tension")


class WorldRules(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.runs = [simulate(seed, 40, profile) for profile in PROFILES for seed in (3, 21)]
        # longer, harsher runs: these seeds once exposed within-the-hour ordering bugs
        cls.runs += [simulate(seed, 60, "crisis") for seed in (50, 78)]

    def test_integrity_checks_pass(self):
        for sim in self.runs:
            with self.subTest(seed=sim.config.seed, profile=sim.config.profile):
                problems = {k: v[:3] for k, v in check_simulation(sim).items() if v}
                self.assertEqual(problems, {})

    def test_transfers_cannot_overdraw(self):
        sim = simulate(3, 1)
        rid = sim.ids[0]
        with self.assertRaises(SimulationError):
            sim.transfer("cash", f"wallet:{rid}", "outside", sim.residents[rid].cash + 1, "E000001")

    def test_mistaken_memories_leave_history_alone(self):
        sim = self.runs[-1]
        digest = sim.log.digest()
        mistaken = [b for b in sim.beliefs.values() if b.error]
        self.assertTrue(mistaken, "expected at least some mistaken or distorted beliefs")
        for b in mistaken[:50]:
            if b.event:
                self.assertIn(b.event, sim.log.by_id)
        self.assertEqual(digest, sim.log.digest())

    def test_people_mostly_resolve_conflict_without_violence(self):
        conf = sum(s.stats["confrontations"] for s in self.runs)
        assaults = sum(s.stats["assaults"] for s in self.runs)
        self.assertGreater(conf, 0)
        self.assertLess(assaults / conf, 0.25)

    def test_quiet_runs_are_valid(self):
        sim = simulate(4, 2)
        self.assertEqual(check_simulation(sim)["locations"], [])
        self.assertIsInstance(sim.incidents, list)


if __name__ == "__main__":
    unittest.main()
