# From the Python prototype to a Godot game

Project Mystery now has two parts that share one data contract:

* **The Python laboratory** (`mystery/`). It simulates towns, keeps the objective history, generates witnesses,
  evidence and cases, runs diagnostics and batch reports, and holds the acceptance tests. It is unchanged in
  behaviour: event-log digests for the same seeds are identical before and after the migration.
* **The Godot 4 game** (`godot/`). It is a native Windows program that plays generated cases with a clickable
  detective interface. It never runs Python and never needs a terminal, network or keys.

The two meet at a **case package** (`.mcase`, see [`case-format.md`](case-format.md)). The **investigation rules**
are implemented on both sides and kept identical by parity tests (see
[`investigation-rules.md`](investigation-rules.md)).

## The layers

The concept separates six concerns. This is where each one lives today and where it will live in Godot.

| Layer | Python today | Godot today | Godot later |
|---|---|---|---|
| World simulation (time, places, money, goods, work) | `mystery/sim/world.py`, `engine.py`, `actions.py`, `config.py` | — | `godot/scripts/sim/` |
| Character decisions and memories | `sim/decisions.py`, `sim/memory.py` | — | `godot/scripts/sim/` |
| Objective event history | `sim/events.py` (append-only log, SHA-256 digest) | sealed inside each case package | `godot/scripts/sim/` |
| Witness and evidence generation | `cases/export.py`, `cases/testimony.py`, `cases/suitability.py` | the `investigation` view of a package | `godot/scripts/sim/` → package |
| Player investigation (rules) | `investigate/session.py`, `dialogue.py`, `notebook.py`, `verdict.py` | `godot/scripts/core/` (rules, plus `town.gd`: where you are, who is where) | unchanged |
| Presentation | `investigate/repl.py` (text), `launcher.py` | `godot/scripts/ui/`: the town (world layer) and the tablet (personal layer) | unchanged |

The rules and the presentation are separated in Godot as they are in Python. `scripts/core/` has no UI code: it
works on plain dictionaries and returns plain results, and the tests drive it without a window.
`scripts/ui/` holds no rules: every button calls the engine and draws what comes back. The seal is opened
in one place in the game, `scripts/core/verdict.gd`, and only once the case is concluded. Outside the game,
only the format tests call the unseal function.

### Godot source map

```text
godot/
  project.godot, export_presets.cfg     Godot 4.3 project and the "Windows Desktop" export
  scenes/main.tscn                      the single scene; everything else is built in code
  cases/                                the bundled library: *.mcase + index.json (with sha256 per file)
  scripts/core/
    case_format.gd    read, validate and (for the verdict only) unseal case packages
    investigation.gd  the rules: questioning, permissions, notebook, hints, timeline, conflicts, theory
    town.gd           the world layer: moving, who is where, and acting only where you are
    verdict.gd        scoring and the reveal model; the only code that opens the seal
    case_library.gd   bundled and imported cases
    save_store.gd     autosaves (one per case) and settings under user://
    clock.gd          minutes to "Day 3 14:20"
    smoke.gd          the self-test the exported .exe runs in CI
  scripts/ui/
    main.gd                 main menu, New Case, Load Case, Settings, dialogs
    investigation_screen.gd the town: map, where you are, conversations, record books, vehicles
    town_map.gd             the drawn street plan with buildings and the people you have seen
    tablet.gd               the investigator's tablet: notes, notebook, evidence, people, timeline,
                            theory, hints, locked case files
    timeline_chart.gd, reveal_screen.gd, theme_builder.gd, kit.gd
  scripts/sim/        reserved for the in-engine simulation (empty by design)
  tests/              headless test runner, suites and the parity fixtures
```

## Playing: the town and the tablet

The game has two layers, so that an investigation feels like going places rather than operating screens.

* **The town (world layer).** The case's places are buildings on a compressed street plan: homes on two lanes,
  trades on the high street, and the square, the road and the mill on the main road. You arrive in the square
  and click a building to go there. The panel beside the map shows where you are:
  * who is here, and talking to them (topics, follow-ups, pressing, the conversation so far);
  * looking around;
  * the record books kept here: the ledger at the shop, bar tabs at the pub, the patient log at the clinic,
    the job book at the workshop;
  * the vehicles parked here.

  People you have seen stay marked on the map, and clicking one walks you back to them. People are where the
  simulation left them when the case begins (`now_at`), so finding them is part of the work. The simulation
  produces no letters or private papers, so none appear; homes hold only the traces that events left there.
* **The tablet (personal layer).** Press T, or the Tablet button, to open it over the town, and again to put it
  away. It holds:
  * case notes and progress;
  * the notebook, with marks and your own notes;
  * evidence (what you found, what you copied, and the books you asked for, with a button to walk back to
    them);
  * a people directory (where you saw each person, what they told you, and "Go to");
  * the timeline;
  * the theory and the reveal;
  * hints;
  * case files.

  The tablet never questions anyone or reads a book remotely: those happen in town. The other cases in the
  library appear as locked case files, shown for the feel of a working tablet. They are disabled buttons
  wired to nothing, and the end-to-end test proves that none of them can be opened from an active
  investigation.

The town's rules live in `scripts/core/town.gd`, with no UI code, and are tested on every bundled case
(`tests/test_town.gd`). The tablet and the map only call them.

## Data flow

```text
 Python laboratory                                   Godot game
 ─────────────────                                   ──────────
 simulate (seed, profile, days)                      New Case / Load Case
   → objective event log  ─┐                           → case_format.validate()
 incident noticed          │ export                    → Investigation (rules, autosave)
   → freeze, recall memory ├──────► .mcase ─────────►     ask / press / search / read / note / mark
   → testimony, evidence   │   investigation (open)       hints, timeline, conflicts
   → suitability, hints    │   sealed_truth  (sealed)   → submit theory / give up
 build-library / export-godot                          → Verdict: unseal once, score, reveal
```

The game uses the cases exactly as the simulation produced them. Nothing is scripted, edited or invented on
the way: the exporter only re-encodes the two views that `export-case` already wrote. The library index stores
each file's SHA-256, and the game refuses a bundled case whose bytes have changed.

### Keeping the truth sealed

* The package's `investigation` view cannot hold truth fields or event ids. The Python and Godot validators
  both reject such a package, and the same check runs in CI on every bundled case.
* Menus show only the `summary` card. It holds the title, town, start, season and a difficulty that comes from
  the suitability verdict (`gentle`, `standard`, `hard`, `very hard`), never from the answer.
* Saves contain only the player's state: notebook, conversations, credits, theory and, after the reveal, the
  score. A test proves that no truth field ever reaches a save.
* `Verdict.reveal()` refuses while the case is open, and a counter (`Verdict.unseal_count`) lets the tests and
  the smoke test prove that the seal was never opened during play.
* The game prints nothing about cases. A case that fails to load is reported to the player by file name and
  reason only.

The seal is a spoiler guard, not encryption. Anyone determined can open it with the documented tools.

## Proof that the rules match

1. `python -m mystery build-library --parity godot/tests/parity` plays a scripted investigation per incident
   family through the Python rules. It covers questions, pressing, the dead, refusals, searches, records,
   citations, notes, marks, every hint tier, the timeline, the state, and then submitting, giving up or an
   "unresolved" theory, followed by the reveal. Every structured result is recorded.
2. `godot/tests/test_parity.gd` replays every action in Godot and compares the results field by field, from the
   first answer to the last line of the reveal.
3. `tests/test_package.py` re-runs the fixtures in Python, so a rules change on the Python side without
   regenerating the fixtures fails the Python tests too.

The other Godot suites cover case loading and validation, testimony rules (guarded, evasive, patience, the
dead), permissions for places, vehicles and records, hints, the spoiler boundary, timeline conflicts (with
expectations computed by Python), save and resume, and an end-to-end investigation through the real interface:
menu, new case, arrive, walk, talk, press, look around, read a book where it is kept, examine a vehicle,
click a person on the map, the tablet's pages (including trying to open locked case files), the T key, leave,
Continue at the same spot, submit, reveal. The town suite checks presence, routing, and where records and
vehicles can be used on all 15 cases, and that the town never opens the seal. Along the way
the end-to-end test checks the computed layout of every screen. It runs again at the largest text size, and
fails on squeezed text, collapsed buttons or anything that runs off the window. Headless Godot lays out
Controls with real font metrics, so these sizes are the ones a player gets. It does not draw, so colours and
looks are not tested.

## Versions

| Version | Where | Bump when |
|---|---|---|
| `SIM_VERSION`, `CONFIG_VERSION` | `mystery/__init__.py` | simulation behaviour or tuning changes (old seeds then tell different stories) |
| `format_version` | `mystery/cases/package.py`, `case_format.gd` | a field of the `.mcase` package is removed, renamed or changes meaning |
| `schema` (`investigation/0.2`) | the player-safe view | the investigation view changes shape (0.2 added `residents[].now_at`) |
| `STATE_VERSION` | `investigation.gd`, `save_store.gd` | the save layout changes (older saves are upgraded in `_normalize_state`; newer ones are refused rather than misread). 2 added the town and the tablet. |

After any change that alters generated cases, regenerate the library and the parity fixtures, then run both
test suites:

```bash
python -m mystery build-library --parity godot/tests/parity
```

```bash
python -m unittest discover -s tests -t .
```

```bash
python -m mystery build-library --check
```

The Godot tests run in CI (see below), or locally with Godot 4.3:

```bash
godot --headless --path godot -s res://tests/run_tests.gd
```

Each save records a fingerprint of the case contents (`Investigation.fingerprint`). If a rebuild changes a
case, its old save is not applied to the new contents. The player is told that the case changed, and it
starts from a fresh notebook. Cases that the rebuild leaves unchanged keep their saves.

## Porting the simulation later

The port is deliberately not done yet. The simulation is the most valuable and most fragile part of the
project, and rewriting it in a hurry would risk its integrity. The plan is to port it in the same way the rules
were ported: one layer at a time, with Python as the oracle.

1. **Random streams and the event log.** Port `mystery/rng.py` and `sim/events.py`. Seeds are SHA-256
   derived, which Godot reproduces with `HashingContext`. The streams themselves are CPython's
   `random.Random` (Mersenne Twister), so the port needs a GDScript Mersenne Twister. It must seed the way
   CPython does and match `random()`, `randrange`, `choice`, `shuffle`, `gauss` and the other calls the
   simulation makes. Godot's own `RandomNumberGenerator` (PCG) cannot be used. Test: identical streams for a
   set of seeds, then identical event digests for an empty town.
2. **World and actions.** Port places, households, accounts and `transfer`, the clock, and the scheduled
   routines. Test: per-tick digests equal to Python for each profile and for a set of seeds.
3. **Decisions.** Port needs, goals and utility scoring. Floating point must follow Python's order of
   operations. Where it cannot, round at the same points on both sides. Test: whole-run digests.
4. **Perception and memory.** Port the broadcast, sightings, beliefs, rumour drift and forgetting. Test: the
   belief stores are equal at the frozen instant.
5. **Incidents and export.** Port detection, freezing, testimony, suitability and hints, and have them write
   the same `.mcase` the Python exporter writes. Test: byte-identical packages for the bundled seeds.
6. **In-game generation.** Add "Generate a new town" to the New Case screen, running the simulation in a
   background thread. The rules, the saves and the interface already work on packages, so nothing else changes.

Until step 5 is complete, the Python laboratory remains the reference and the only source of new cases.

## Building the Windows game

CI (`.github/workflows/ci.yml`, job *Godot game*) runs on `windows-latest`:

1. It installs Godot 4.3-stable and only the Windows export templates.
2. It imports the project and runs the Godot tests. Any script error fails the job.
3. It exports `ProjectMystery.exe` with the game data embedded (`embed_pck`).
4. It runs the exported executable headless with `--smoke-test`. The executable loads every bundled case,
   plays a little, checks that the seal stays shut until the case is concluded and opens afterwards, and
   writes `SMOKE OK`.
5. It uploads the folder as the artifact **ProjectMystery-windows**.

To build locally, open `godot/project.godot` in Godot 4.3, install the export templates (*Editor → Manage
Export Templates*), and choose *Project → Export → Windows Desktop*.

## Known limitations

* **Python and Godot equivalence covers the rules, not the simulation.** New towns are still generated in
  Python, and the game ships with a fixed library of 15 cases. Players can import more `.mcase` files.
* The interface has been exercised by automated tests, not yet by human playtesting. Pacing, wording,
  difficulty labels and the town map's look need real players.
* Time stands still during an investigation: people stay where they were when the case began, so nobody moves
  around town while you investigate. Moving people would need the simulation in the game (see above).
* The executable is not code-signed, so SmartScreen warns on first launch.
* The game uses the Compatibility (OpenGL 3.3) renderer for wide hardware support. Very old graphics drivers
  may still fail to start it.
* The case seal deters accidental spoilers. It does not protect the truth from someone determined to read it.
