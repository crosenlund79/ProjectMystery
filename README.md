# Project Mystery

> *Build a town that produces true histories — and let the player discover how difficult it is to know the truth.*

A prototype of the concept in [`docs/concept.md`](docs/concept.md), in two parts: a **Godot 4 game** with a
clickable detective interface, and the **Python laboratory** that simulates the towns and generates the cases.
A seeded town of 8–12
residents lives its own life for weeks — working, drinking, borrowing, arguing, making up, and occasionally
stealing, crashing a car or hurting someone. The simulation records what *really* happened. When something is
noticed, the case is frozen. You then investigate it through what people actually saw, heard, were told or
are willing to say. When you submit a theory or give up, the sealed truth is revealed next to your notebook.

There's no scripting. Every clue, lie, rumour and mistake comes from simulated state.

## Play the game on Windows

The game needs no Python, no installer, no internet connection and no accounts or keys.

1. Open the repository's **Actions** tab, choose the latest successful **CI** run, and download the artifact
   **ProjectMystery-windows** at the bottom of the page. You need to be signed in to GitHub. Artifacts are
   kept for 90 days, and any new push builds a fresh one.
2. Right-click the downloaded `.zip`, choose **Extract All…**, and open the folder.
3. Double-click **`ProjectMystery.exe`**. If Windows shows "Windows protected your PC", choose **More info → Run
   anyway**. The game is not code-signed yet.

Choose **New Case** and pick one of the 15 bundled cases, each taken from its own simulated history.
Then investigate:

* talk to people (pick a topic, follow up on names they mention, press someone who is holding back);
* look around places and vehicles (private ones need the owner's agreement);
* read the record books.

Everything you learn is filed in the notebook. The timeline lines up who was where, and flags accounts that
cannot both be true. When you are ready, choose **Solve the case…** to submit your theory, or give up, and the
sealed truth is revealed and scored. The game saves after every action. **Continue** picks up where you left
off, **Load Case** opens other saved investigations or imports a `.mcase` file, and **Settings** has text size,
high contrast and fullscreen. Saves live in `%APPDATA%\ProjectMystery`.

To run the game from source, open `godot/project.godot` in [Godot 4.3](https://godotengine.org/download/archive/4.3-stable/)
and press F5. [`docs/godot-migration.md`](docs/godot-migration.md) explains how the game and the laboratory fit
together, how cases travel between them ([`docs/case-format.md`](docs/case-format.md)), how their rules are
kept identical ([`docs/investigation-rules.md`](docs/investigation-rules.md)), and the plan for moving the
simulation itself into Godot.

## The Python laboratory

The laboratory is pure Python 3.10+, with no dependencies. It works on Windows, macOS and Linux. It runs the
simulation, the developer tools, the original text version of the game, and the case pipeline for the Godot
game:

```bash
python -m mystery export-godot --seed 7 --days 60 --profile normal --incident I1
```

```bash
python -m mystery build-library --parity godot/tests/parity
```

```bash
python -m mystery validate-case godot/cases/*.mcase
```

The first command packages one case for the game. The second rebuilds the bundled library and the
Python-to-Godot parity fixtures. The third checks packages.

### Windows: double-click the laboratory and the text game

1. Install Python 3.10 or newer from [python.org](https://www.python.org/downloads/windows/). On the first
   screen of the installer, tick **Add python.exe to PATH**. (Alternatively, run
   `winget install -e --id Python.Python.3.12`, or install Python 3.12 from the Microsoft Store.)
2. Download or clone this repository. If you downloaded a `.zip`, right-click it and choose **Extract All…**;
   the launchers must stay next to the `mystery` folder.
3. Double-click one of the launchers:

| Launcher | What it is for |
|---|---|
| **`Play-Mystery.cmd`** | **The game, spoiler-free.** Start a new case (pick the kind of season and how much the town gives away), open a saved case, or read how to play. It never shows anything from the sealed truth. The truth appears only through the in-game `reveal` command, after you submit a theory or give up. |
| **`Mystery-Lab.cmd`** | **The simulation laboratory, with spoilers.** Simulate towns and see who did what, run batch reports, find and export cases, read a case's sealed truth, check replays, and run the test suite. Each action prints the equivalent `python -m mystery ...` command. |

Both launchers find Python by trying `MYSTERY_PYTHON`, then `py -3`, then `python`, then `python3`, and they
accept only version 3.10 or newer. If no suitable Python is found, they explain how to install one. If anything
goes wrong, the window stays open so you can read the message. Cases and notes are saved under `runs\cases`,
so you can close the window and continue later.

Troubleshooting:

* **"Windows protected your PC"** (SmartScreen) can appear for files downloaded from the internet. Choose
  **More info → Run anyway**, or right-click the file, then **Properties → Unblock**.
* **Python is installed but isn't found.** Close and reopen the window first. If it still fails, turn off the
  `python.exe` and `python3.exe` entries under *Settings → Apps → Advanced app settings → App execution aliases*
  (they are Microsoft Store placeholders). Or set `MYSTERY_PYTHON` to the full path of `python.exe`.
* The command line works on Windows too: use `py -m mystery ...` wherever this README says `python -m mystery`.

The menus behind the launchers also work on any OS: `python -m mystery.launcher play` or
`python -m mystery.launcher lab`.

## Quick start (command line)

```bash
python -m mystery simulate --seed 7 --days 60 --profile normal
```

```bash
python -m mystery export-case --seed 7 --days 60 --profile normal --incident I1
```

```bash
python -m mystery investigate --case runs/cases/7-normal-60d-r10-I1
```

`simulate` lists the incidents somebody noticed (only their hooks, unless you pass `--spoilers`) with a suitability verdict for each. Pick one marked `playable` and export it.
To have the tool search seeds for a case instead (an explicit developer case-selection mode, which never
alters any history):

```bash
python -m mystery find-case --profile scarcity --family theft --verdict playable --export
```

Inside a case, `help` lists the commands. The core loop is `talk <name>` (lettered topics; `p` plus a letter
presses someone who is holding back), `inspect <place or vehicle>`, `read <ledger|tabs|clinic|workshop>`,
`notebook`, `timeline`, `hint`, `submit` and `reveal`.

```text
CASE: The Lighter Savings Tin
Greyford — Day 25 09:00

Selma Ash opened the Ash household savings tin on Day 25 and found 1235 crowns fewer than there
  should be. It was last counted Day 23 07:00.

The time in question: from about 07:00 on Day 23 to 07:00 on Day 25.

> talk agnes

AGNES — ask about what? (letter; p+letter to press; ? lists topics; back)
  A. Where they were during the time in question
  B. What they saw or heard during that time
  ...
agnes> B
AGNES: I saw Arvid at Mill Road around 07:15 on Day 23, heading toward the mill.  [S1]
  I saw Greta at the grocery from about 10:00 to 11:00 on Day 23.  [S2]
  I saw Nora at the grocery around 13:00 on Day 23.  [S3]
  I saw Clara at the square around 17:00 on Day 23, the old blue hatchback heading toward the
    Drover's Rest.  [S4]
  I saw Clara, Felix and Nora at the Drover's Rest from about 19:00 to 21:00 on Day 23.  [S6-S8]
  ...
```

(Seed numbers stay valid only for the code and config versions that produced them; see *Determinism* below.)

Other developer commands:

| Command | Purpose |
|---|---|
| `simulate-batch --runs 1000 --days 60 --profile scarcity` | headless batch with the diagnostic report (parallel) |
| `list-incidents --seed S [--spoilers]` | incidents of one run, with case suitability |
| `replay --seed S` | re-run a saved run and verify the event-log digest |
| `truth --case DIR` | print a case's sealed truth (spoilers) |
| `reveal --case DIR` | reveal after concluding, from the shell |
| `investigate --case DIR --script FILE` | drive a session from a file of commands |

Profiles: `normal`, `scarcity` (dear food, short deliveries), `crisis` (wage cuts, a lay-off, more debt) and
`tension` (old grudges, heavy drinking, short tempers).

## Determinism

A run is fully determined by its seed, profile, length and resident count, together with `SIM_VERSION` and
`CONFIG_VERSION` in `mystery/__init__.py`. All randomness comes from SHA-256-derived streams, never from
`hash()`. Every saved run and case records those versions, and `replay` warns when they differ. Any change to
behaviour or tuning should bump `CONFIG_VERSION`, because old seeds will then tell different stories.

## How it works

The project's central rule: keep these five layers apart.

| Layer | Where | What it holds |
|---|---|---|
| Objective history | `sim/events.py`, `sim/world.py` | Append-only event log with ids, times, places, actors, intent and causal links. All money and goods move through `transfer`, which refuses to overdraw. |
| Perception | `sim/engine.py` (`broadcast`, sightings, co-presence) | Who could physically notice what: same place, line of sight, darkness, distance, hearing through walls, being asleep or drunk. |
| Belief and memory | `sim/memory.py` | Each resident's claims, tagged by source (*self, saw, heard, told by X, inferred*), with confidence, salience, provenance and any distortion. These include misidentification in the dark, rumours that drift in time or lose their hedging, wrong suspicions, lies passed on, and forgetting. |
| Physical evidence and records | `world.add_evidence`, `world.record` | Each trace exists only because an event made it: a forced latch, debris, a dented car, a hidden till bag, blood. Each record is written by a world event: ledger lines (including a clerk's duplicate entry), bar tabs, clinic notes, workshop job cards with the customer's explanation. |
| Player knowledge | `investigate/` | Only what you have been told, seen or read, plus your own notes and marks. |

**Decisions** (`sim/decisions.py`) are needs, goals and utility scoring with bounded noise. Pressure (debt,
hunger, rent, lay-offs) changes priorities and acceptable risk. It never forces an outcome. Lawful off-ramps
always compete with the alternatives: borrowing, credit at the grocery, casual work, helping a friend,
apologising, promising to pay by next week, walking away. Wrongdoing is only a candidate when need,
temperament and an opportunity line up.

**Incidents** (`sim/incidents.py`). The current families are theft (tills, stock, household savings),
bookkeeping errors (*no crime*), assault arising from an argument (rarely fatal), vehicle collisions (drunk
or sober, with fence or pedestrian, stopping or fleeing) and drunken falls (*accident*). An incident becomes a case
only when someone in town notices it. The case is frozen an hour or two after discovery, never in the dead of night.

**Cases** (`cases/export.py`). At the frozen instant, each resident's memory is recalled (with decay,
rehearsal of the incident night and occasional misremembered times) and turned into first-person testimony.
Each claim is marked *open*, *guarded* (only if pressed, e.g. out of loyalty or uncertainty) or *withheld*
(self-protection). A person responsible for the incident lies about where they were if no one saw the act. They also
explain away a dent ("hit a deer") or claim the other person started the fight. Two files are written:

* `investigation.json` is player-safe. It holds the hook, people, places, rendered testimony, reachable traces and records,
  consent decisions and a hint ladder. It contains no event ids, intents, accuracy flags or causal links, and
  `check_spoiler_boundary` enforces this.
* `truth.json` is developer-only. It holds the incident, its causal chain, the culprit's movements, private states,
  and an audit of every statement: accurate, mistaken (and why) or a lie (and why).

**Suitability** (`cases/suitability.py`) keeps "did something interesting happen?" separate from "can a careful
player infer it?" It counts *independent* channels that point at the truth and that the player can actually reach:
witnesses (grouped by who originally perceived the thing, so a rumour told nine times is one source), physical
traces, documentary records and contradictions with the culprit's lie. The verdict is `obvious`,
`playable`, `ambiguous` or `unsolvable`. Hints are generated only from those channels.

**The player** is a local who has just come back after months away. That sidesteps pre-case knowledge.
You have no official power: private homes, back rooms and record books need their owner's consent, and a
refusal is itself information. Theories are scored on explanation, responsibility, motive and the evidence you
cite, minus hints. An honest "unresolved" scores well when the evidence really was thin.

## Acceptance checks

All of these run with `python -m unittest discover -s tests -t .` (about 25 seconds), or with option 7 in
`Mystery-Lab.cmd`. The Godot game has its own suite (`godot --headless --path godot -s res://tests/run_tests.gd`).
It covers case loading, testimony, permissions, hints, the spoiler boundary, saves, the reveal, an
end-to-end investigation through the interface, and a step-by-step replay of investigations recorded from the
Python rules. CI runs both suites on Windows, then exports the game and smoke-tests the executable.

| Check (from the concept, §12) | How it is verified |
|---|---|
| Same seed and versions reproduce the same timeline | `test_determinism`: in-process, across `PYTHONHASHSEED` values, early stopping, CLI `replay` |
| Nobody at two incompatible places at once | `integrity.check_locations` + `check_event_locations` on every profile |
| Nobody spends money or goods they don't have | `transfer` refuses overdrafts; `check_accounts` replays every transfer |
| Truthful statements trace to perception or a named source | `check_beliefs` (perception records, co-location when told, premises) + `check_case` |
| Memory can be wrong without changing history | mistaken beliefs exist with error causes; the log digest is unchanged |
| Evidence comes from world events, never inserted for convenience | `check_evidence`: every trace and record points at the event that made it |
| The player view cannot access the sealed log | `test_spoiler_boundary`: no truth fields, `truth.json` never opened during play, works with it deleted |
| Outcomes include accident, no crime and unresolved | `test_cases.Outcomes` |
| One incident playable from start to theory to reveal | `test_cases.EndToEnd` drives the text UI through a whole case |
| Batch report separates quiet runs, major incidents, candidates and suitable cases | `test_cases.Batch` + `simulate-batch` |

### Testing the Windows launchers

`tests/test_launchers.py` exercises the menus behind both launchers on every OS using scripted input. It checks
that the gameplay flow never reads `truth.json` until a case is concluded. It also checks the `.cmd` files
statically: CRLF line endings, `py`/`python` search order, the 3.10 minimum, and that the window is held on
errors. When the suite runs on Windows, it executes both launchers for real.

On Linux, `python3 tools/wine/run_launcher_tests.py` runs both `.cmd` files through Wine's real `cmd.exe`
(it needs the `wine` and `gcc-mingw-w64-x86-64` packages). The `py.exe` and `python.exe` it puts on the path
are small shims built from `tools/wine/shim.c`. They forward to the local Python, or pretend to be an old one,
so no downloaded Windows binaries are run. It covers 14 scenarios:

* Python found through `py`, through `python` or through `MYSTERY_PYTHON` (with spaces in the path).
* No Python at all, and only Python 3.8.
* A crash that keeps the window open, and `MYSTERY_NO_PAUSE`.
* A launcher copied out of its folder.
* A full play session: generating, continuing, giving up and revealing, with no truth leaking before the reveal.
* The lab menu.

## Repository map

```text
mystery/
  sim/          world, residents, decisions, actions, events, memory, incidents, engine, config
  cases/        export (truth + investigation views), testimony rendering, suitability and hints
  investigate/  session (spoiler-safe), dialogue, notebook, verdict (the only truth reader), text UI
  diagnostics/  integrity checks and batch reports
  cli.py        python -m mystery ...
  launcher.py   the menus behind the launchers (play: spoiler-free; lab: developer tools)
  cases/package.py, cases/library.py   .mcase packages, the bundled library and parity fixtures
godot/          the Godot 4.3 game (see docs/godot-migration.md)
  scripts/core/ case loading, investigation rules, verdict, saves (no UI)
  scripts/ui/   menus, investigation screen, timeline, reveal, theme
  scripts/sim/  reserved for the in-engine simulation
  cases/        the bundled case library; tests/  Godot tests and parity fixtures
Play-Mystery.cmd, Mystery-Lab.cmd   double-click launchers for Windows (Python laboratory and text game)
tools/          find-python.cmd (shared by the launchers); wine/ launcher test harness
tests/          unittest acceptance suite
docs/           concept, prototype notes, case format, investigation rules, Godot migration
.github/        CI: Python tests (Windows, Linux), Godot tests, Windows export and smoke test
runs/           generated runs and cases (git-ignored)
```

See [`docs/prototype-notes.md`](docs/prototype-notes.md) for measured batch results, the tuning history,
known limitations and suggested next steps.
