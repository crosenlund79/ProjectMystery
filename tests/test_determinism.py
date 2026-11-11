"""Acceptance: the same seed and the same code/config versions reproduce the same history."""

import os
import subprocess
import sys
import tempfile
import unittest

from mystery.cli import main
from mystery.sim.engine import simulate

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SNIPPET = ("import sys; sys.path.insert(0, %r); from mystery.sim.engine import simulate; "
           "print(simulate(7, 25, 'tension').log.digest())" % ROOT)


class Determinism(unittest.TestCase):
    def test_same_seed_same_timeline(self):
        a = simulate(7, 25, "tension")
        b = simulate(7, 25, "tension")
        self.assertEqual(a.log.digest(), b.log.digest())
        self.assertEqual(len(a.beliefs), len(b.beliefs))
        self.assertEqual([e.to_dict() for e in a.log.events[:200]], [e.to_dict() for e in b.log.events[:200]])

    def test_independent_of_python_hash_seed(self):
        digests = set()
        for hash_seed in ("1", "12345"):
            env = {**os.environ, "PYTHONHASHSEED": hash_seed}
            out = subprocess.run([sys.executable, "-c", SNIPPET], env=env, capture_output=True, text=True, check=True)
            digests.add(out.stdout.strip())
        self.assertEqual(len(digests), 1)
        self.assertEqual(digests.pop(), simulate(7, 25, "tension").log.digest())

    def test_different_seeds_differ(self):
        self.assertNotEqual(simulate(1, 10).log.digest(), simulate(2, 10).log.digest())

    def test_stopping_early_does_not_change_the_past(self):
        full = simulate(11, 20)
        part = simulate(11, 20, until=10 * 1440)
        cutoff = 10 * 1440 - 60
        self.assertEqual(full.log.digest(until=cutoff), part.log.digest(until=cutoff))

    def test_cli_replay_matches_saved_run(self):
        with tempfile.TemporaryDirectory() as tmp:
            args = ["--seed", "5", "--days", "15", "--profile", "normal", "--out", tmp]
            with open(os.devnull, "w") as devnull:
                stdout, sys.stdout = sys.stdout, devnull
                try:
                    self.assertEqual(main(["simulate", *args]), 0)
                    self.assertEqual(main(["replay", *args]), 0)
                finally:
                    sys.stdout = stdout


if __name__ == "__main__":
    unittest.main()
