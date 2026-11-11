"""The double-clickable Windows launchers and the menus behind them.

The menus (mystery/launcher.py) are tested on every OS with scripted input. The .cmd files
are checked statically everywhere and executed for real when the suite runs on Windows.
On Linux, tools/wine/run_launcher_tests.py runs them through Wine's cmd.exe.
"""

import builtins
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

from mystery import launcher
from mystery.diagnostics.batch import peak_memory_mb, run_batch

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLAY, LAB, FIND = "Play-Mystery.cmd", "Mystery-Lab.cmd", os.path.join("tools", "find-python.cmd")


def scripted(lines):
    """A Console fed from a list of lines; returns (console, output list)."""
    feed = iter(lines)
    out = []

    def read(prompt):
        out.append(prompt)
        try:
            return next(feed)
        except StopIteration:
            raise EOFError from None

    return launcher.Console(read=read, write=out.append), out


def read_raw(name):
    with open(os.path.join(ROOT, name), "rb") as f:
        return f.read()


class CmdFiles(unittest.TestCase):
    def test_batch_files_use_crlf_and_plain_ascii(self):
        for name in (PLAY, LAB, FIND):
            raw = read_raw(name)
            with self.subTest(name=name):
                raw.decode("ascii")
                self.assertNotIn(b"\n", raw.replace(b"\r\n", b""), "every line must end in CRLF")
        with open(os.path.join(ROOT, ".gitattributes"), encoding="utf-8") as f:
            self.assertIn("*.cmd text eol=crlf", f.read())

    def test_launchers_find_python_and_hold_the_window_on_errors(self):
        for name, mode in ((PLAY, "play"), (LAB, "lab")):
            text = read_raw(name).decode("ascii")
            with self.subTest(name=name):
                self.assertIn('cd /d "%~dp0"', text)  # double-click from anywhere, spaces in paths
                self.assertIn(r'call "%~dp0tools\find-python.cmd"', text)
                self.assertIn(f"%PY_CMD% -m mystery.launcher {mode}", text)
                self.assertIn('if "%RC%"=="0" goto :done', text)  # success closes without a pause
                self.assertIn("python.org/downloads/windows", text)
                self.assertIn("winget install", text)
                self.assertGreaterEqual(text.count("call :hold"), 3)  # error, no Python, no package
                self.assertIn("pause >nul", text)
                self.assertIn("MYSTERY_NO_PAUSE", text)

    def test_gameplay_launcher_has_no_spoiler_route(self):
        code = [line for line in read_raw(PLAY).decode("ascii").lower().splitlines()
                if not line.lstrip().startswith("rem")]
        text = "\n".join(code)
        for word in ("truth", "spoiler", " lab", "reveal"):
            self.assertNotIn(word, text)

    def test_python_search_order_and_minimum_version(self):
        text = read_raw(FIND).decode("ascii")
        order = [text.index(s) for s in ('"%MYSTERY_PYTHON%" -c', "py -3 -c", "python -c", "python3 -c")]
        self.assertEqual(order, sorted(order))
        self.assertIn(">= (3, 10)", text)
        self.assertNotIn("findstr", text)  # not available everywhere (e.g. Wine)

    @unittest.skipUnless(os.name == "nt", "runs the real launchers on Windows only")
    def test_launchers_run_on_windows(self):
        env = {**os.environ, "MYSTERY_NO_PAUSE": "1"}
        for name, answer, marker in ((PLAY, "4\n", "PROJECT MYSTERY"), (LAB, "0\n", "LABORATORY")):
            with self.subTest(name=name):
                proc = subprocess.run(["cmd", "/c", os.path.join(ROOT, name)], input=answer, text=True,
                                      capture_output=True, env=env, timeout=300)
                self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
                self.assertIn(marker, proc.stdout)


class PlayMenu(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.cases = os.path.join(self.tmp, "runs", "cases")

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def _play(self, lines, seed=None):
        console, out = scripted(lines)
        code = launcher.play(console, seed=seed, cases_dir=self.cases)
        return code, "\n".join(out)

    def test_new_case_then_investigate_without_reading_the_truth(self):
        reads = []
        real_open = builtins.open

        def spy(file, mode="r", *a, **kw):
            if "r" in mode and "+" not in mode:
                reads.append(os.path.basename(str(file)))
            return real_open(file, mode, *a, **kw)

        with mock.patch("builtins.open", spy):
            code, out = self._play(["1", "1", "2", "y", "people", "note a first thought", "quit", "4"], seed=7)
        self.assertEqual(code, 0)
        self.assertIn("A case is waiting:", out)
        self.assertIn("CASE:", out)
        self.assertNotIn("truth.json", reads)
        [case] = os.listdir(self.cases)
        with open(os.path.join(self.cases, case, "truth.json"), encoding="utf-8") as f:
            truth = json.load(f)
        self.assertNotIn(truth["narrative"], out)
        self.assertNotIn("responsible", out.lower())

    def test_saved_case_continue_conclude_and_list_as_closed(self):
        self._play(["1", "1", "2", "n", "4"], seed=7)
        listed = launcher.list_cases(self.cases)
        self.assertEqual([c["status"] for c in listed], ["new"])
        code, out = self._play(["2", "1", "reveal", "giveup", "reveal", "quit", "4"])
        self.assertEqual(code, 0)
        self.assertLess(out.index("The truth stays sealed"), out.index("THE TRUTH"))
        self.assertTrue(launcher.list_cases(self.cases)[0]["status"].startswith("closed"))
        code, out = self._play(["2", "1", "r", "", "4"])  # read the reveal again
        self.assertIn("THE TRUTH", out)

    def test_existing_case_is_never_overwritten(self):
        self._play(["1", "1", "2", "y", "note keep me", "quit", "4"], seed=7)
        self._play(["1", "1", "2", "n", "4"], seed=7)  # same seed finds the same case
        [case] = launcher.list_cases(self.cases)
        self.assertTrue(case["status"].startswith("in progress"))

    def test_bad_answers_are_asked_again_and_eof_leaves_quietly(self):
        console, out = scripted(["9", "x", "3", ""])
        with self.assertRaises(EOFError):
            launcher.play(console, cases_dir=self.cases)
        self.assertIn("  Please choose one of: 1, 2, 3, 4.", out)
        self.assertEqual(launcher.main(["nonsense"]), 2)


class LabMenu(unittest.TestCase):
    def test_lab_shows_spoilers_and_reuses_the_cli(self):
        with tempfile.TemporaryDirectory() as tmp:
            cwd = os.getcwd()
            os.chdir(tmp)
            try:
                console, out = scripted(["1", "7", "30", "1", "10", "", "0"])
                with mock.patch("builtins.print", lambda *a, **k: out.append(" ".join(map(str, a)))):
                    code = launcher.lab(console, cases_dir=os.path.join(tmp, "runs", "cases"))
            finally:
                os.chdir(cwd)
        text = "\n".join(out)
        self.assertEqual(code, 0)
        self.assertIn("SHOWS SPOILERS", text)
        self.assertIn("python -m mystery simulate --seed 7 --days 30", text)
        self.assertIn("responsible=", text)


class WindowsPortability(unittest.TestCase):
    def test_batch_workers_use_spawn_like_windows(self):
        rep = run_batch(runs=2, days=6, profile="normal", workers=2)
        self.assertEqual(rep["runs"], 2)
        self.assertEqual(rep["runs_with_integrity_failures"], [])

    def test_peak_memory_is_reported_or_none(self):
        value = peak_memory_mb()
        self.assertTrue(value is None or value > 0)

    def test_module_entry_points_are_import_safe(self):
        for module in ("mystery.__main__", "mystery.launcher"):
            proc = subprocess.run([sys.executable, "-c", f"import {module}"], cwd=ROOT, capture_output=True,
                                  text=True, timeout=60)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertEqual(proc.stdout, "")


if __name__ == "__main__":
    unittest.main()
