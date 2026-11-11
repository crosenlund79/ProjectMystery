"""Exercise the Windows launchers on Linux with Wine's cmd.exe.

Wine supplies a real cmd.exe interpreter, so the batch logic is tested as written:
finding Python, error paths, holding the window open, paths with spaces, exit codes.
The `py.exe`/`python.exe` that the launchers find are tiny shims built from shim.c,
which forward to this machine's own Python 3.10+ (or impersonate an old Python).
That means no downloaded Windows binaries are run.

Requirements: wine (cmd.exe) and x86_64-w64-mingw32-gcc.

    python3 tools/wine/run_launcher_tests.py

Set WINEPREFIX to reuse an existing prefix (a new one takes ~20 s to create).
This is a developer check, not part of the unit test suite.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))


NOT_FOUND = (9009, 9009 % 256)  # Linux exit statuses are 8-bit; real Windows keeps 9009


def winpath(p: str) -> str:
    return "Z:" + os.path.abspath(p).replace("/", "\\")


class Harness:
    def __init__(self) -> None:
        for tool in ("wine", "x86_64-w64-mingw32-gcc"):
            if not shutil.which(tool):
                sys.exit(f"missing {tool}; install wine and gcc-mingw-w64-x86-64")
        self.tmp = tempfile.mkdtemp(prefix="mystery-wine-")
        self.prefix = os.environ.get("WINEPREFIX") or os.path.join(self.tmp, "prefix")
        self.results: list[tuple[str, bool, str]] = []
        self.shims = os.path.join(self.tmp, "shims")
        self._build_shims()
        # a copy of the game in a folder whose name contains spaces
        self.game = os.path.join(self.tmp, "My Games", "Project Mystery")
        os.makedirs(self.game)
        for item in ("mystery", "tools", "Play-Mystery.cmd", "Mystery-Lab.cmd"):
            src = os.path.join(ROOT, item)
            dst = os.path.join(self.game, item)
            if os.path.isdir(src):
                shutil.copytree(src, dst, ignore=shutil.ignore_patterns("__pycache__", "wine"))
            else:
                shutil.copy2(src, dst)

    def _build_shims(self) -> None:
        both = os.path.join(self.shims, "both")
        only_python = os.path.join(self.shims, "python-only")
        spaced = os.path.join(self.shims, "Program Files", "Python")
        for d in (both, only_python, spaced):
            os.makedirs(d)
        src = os.path.join(HERE, "shim.c")

        def cc(out: str, *flags: str) -> None:
            subprocess.run(["x86_64-w64-mingw32-gcc", "-O2", *flags, "-o", out, src, "-lshell32"], check=True)

        cc(os.path.join(both, "py.exe"), "-DPY_LAUNCHER")
        cc(os.path.join(both, "python.exe"))
        shutil.copy2(os.path.join(both, "python.exe"), only_python)
        shutil.copy2(os.path.join(both, "python.exe"), spaced)
        self.dirs = {"both": both, "python-only": only_python, "spaced": spaced}
        # an interpreter that passes the version check but whose game run fails
        self.failing = os.path.join(self.tmp, "failing-python.sh")
        with open(self.failing, "w") as f:
            f.write(f'#!/bin/sh\ncase "$*" in *mystery.launcher*) echo "simulated crash" >&2; exit 5;; esac\n'
                    f'exec "{sys.executable}" "$@"\n')
        os.chmod(self.failing, 0o755)

    def run(self, launcher: str, stdin: str, path_dir: str | None = None, env: dict | None = None,
            where: str | None = None) -> tuple[int, str]:
        e = {k: v for k, v in os.environ.items() if not k.startswith(("MYSTERY_", "SHIM_", "WINEPATH"))}
        e.update({"WINEPREFIX": self.prefix, "WINEDEBUG": "-all", "SHIM_TARGET": sys.executable})
        if path_dir:
            e["WINEPATH"] = winpath(path_dir)
        e.update(env or {})
        target = os.path.join(where or self.game, launcher)
        proc = subprocess.run(["wine", "cmd", "/c", winpath(target)], input=stdin, capture_output=True,
                              text=True, env=e, timeout=600, cwd=self.tmp)
        return proc.returncode, proc.stdout + proc.stderr

    def check(self, name: str, ok: bool, detail: str = "") -> None:
        self.results.append((name, ok, detail))
        print(f"{'PASS' if ok else 'FAIL'}  {name}" + (f"  -- {detail}" if detail and not ok else ""))

    # ------------------------------------------------------------------ scenarios
    def scenarios(self) -> None:
        both = self.dirs["both"]

        code, out = self.run("Play-Mystery.cmd", "4\n", both)
        self.check("play: finds 'py -3', shows the menu, quits cleanly", code == 0 and "PROJECT MYSTERY" in out
                   and "Press any key" not in out, out[-400:])

        script = "1\n1\n2\ny\nhelp\npeople\nnote the back door matters\nnotebook\nquit\n4\n"
        code, out = self.run("Play-Mystery.cmd", script, both, {"MYSTERY_SEED": "7"})
        cases = os.path.join(self.game, "runs", "cases")
        made = sorted(os.listdir(cases)) if os.path.isdir(cases) else []
        self.check("play: generates a case into runs\\cases and opens the investigation",
                   code == 0 and len(made) == 1 and "A case is waiting:" in out and "CASE:" in out, out[-600:])
        if made:
            case_dir = os.path.join(cases, made[0])
            with open(os.path.join(case_dir, "truth.json"), encoding="utf-8") as f:
                truth = json.load(f)
            leaks = [s for s in (truth["narrative"], "responsible=", "SPOILERS", "THE TRUTH") if s in out]
            self.check("play: nothing from the sealed truth is shown", not leaks, f"leaked: {leaks}")
            first = json.load(open(os.path.join(case_dir, "investigation.json"), encoding="utf-8"))
            someone = next(r["first"] for r in first["residents"] if r["condition"] != "deceased")
            again = ("2\n1\nc\nask " + someone + " window\nreveal\ngiveup\nreveal\nquit\n4\n")
            code, out = self.run("Play-Mystery.cmd", again, both)
            sealed_first = out.find("The truth stays sealed") != -1 and out.find("The truth stays sealed") < \
                out.find("THE TRUTH")
            self.check("play: reopens the saved case; the truth stays sealed until the case is concluded",
                       code == 0 and "in progress" in out and sealed_first and "SCORE:" in out, out[-600:])
            code, out = self.run("Play-Mystery.cmd", "2\n", both)
            self.check("play: a closed case is listed with its score", "closed — scored" in out, out[-400:])

        code, out = self.run("Play-Mystery.cmd", "4\n", self.dirs["python-only"])
        self.check("play: falls back to 'python' when 'py' is missing", code == 0 and "PROJECT MYSTERY" in out,
                   out[-400:])

        code, out = self.run("Play-Mystery.cmd", "4\n", None,
                             {"MYSTERY_PYTHON": winpath(os.path.join(self.dirs["spaced"], "python.exe"))})
        self.check("play: MYSTERY_PYTHON with spaces in its path is honoured", code == 0 and "PROJECT MYSTERY" in out,
                   out[-400:])

        code, out = self.run("Play-Mystery.cmd", "\n", None)
        self.check("play: no Python -> installation guidance, window held open, exit 9009",
                   code in NOT_FOUND and "python.org/downloads/windows" in out and "winget install" in out
                   and "Press any key to close this window." in out, f"code={code} {out[-500:]}")

        code, out = self.run("Play-Mystery.cmd", "\n", both, {"SHIM_FAKE_VERSION": "3.8.10"})
        self.check("play: only Python 3.8 -> says it is too old",
                   code in NOT_FOUND and "3.8.10, which is too old" in out, f"code={code} {out[-500:]}")

        code, out = self.run("Play-Mystery.cmd", "\n", both, {"SHIM_TARGET": self.failing})
        self.check("play: a crash keeps the window open and reports the exit code",
                   code == 5 and "exit code 5" in out and "simulated crash" in out
                   and "Press any key to close this window." in out, f"code={code} {out[-500:]}")

        code, out = self.run("Play-Mystery.cmd", "\n", both, {"SHIM_TARGET": self.failing, "MYSTERY_NO_PAUSE": "1"})
        self.check("play: MYSTERY_NO_PAUSE skips the hold for automation",
                   code == 5 and "Press any key" not in out, out[-300:])

        lone = os.path.join(self.tmp, "Downloads")
        os.makedirs(lone)
        shutil.copy2(os.path.join(self.game, "Play-Mystery.cmd"), lone)
        code, out = self.run("Play-Mystery.cmd", "\n", both, where=lone)
        self.check("play: launcher copied out of the folder explains the .zip/extract problem",
                   code == 1 and "Extract All" in out, f"code={code} {out[-400:]}")

        lab = "1\n7\n30\n1\n10\n\n5\n1\n\n9\n\n0\n"
        code, out = self.run("Mystery-Lab.cmd", lab, both)
        self.check("lab: simulate with spoilers, show a sealed truth, CLI reference, quit",
                   code == 0 and "LABORATORY" in out and "responsible=" in out and "SPOILERS" in out
                   and "usage: mystery" in out, out[-600:])

        code, out = self.run("Mystery-Lab.cmd", "\n", None)
        self.check("lab: no Python -> guidance and held window", code in NOT_FOUND and "winget install" in out,
                   out[-300:])

    def finish(self) -> int:
        failed = [r for r in self.results if not r[1]]
        print(f"\n{len(self.results) - len(failed)}/{len(self.results)} launcher scenarios passed under Wine.")
        shutil.rmtree(self.tmp, ignore_errors=True)
        return 1 if failed else 0


if __name__ == "__main__":
    h = Harness()
    h.scenarios()
    sys.exit(h.finish())
