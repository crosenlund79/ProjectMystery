# Project Mystery: hibernation notes

> **Status: PARKED / ON HOLD**, indefinitely, from 17 November 2026, to make room for other projects.
> Nothing was deleted or archived. The code, the tests, the CI and the documents are kept exactly as they were
> at the last working build.

This document is the starting point for whoever (including a future us) picks the project up again. It covers:
- why the project stopped, and the question any revival must answer first;
- what exists and works;
- how to run, test and build it;
- what is broken or unfinished;
- which documents to read next.

## Why the project is parked

**The simulation is a technical success.** A seeded town of 8-12 people lives its own life:
- people work, shop, drink, borrow, quarrel, gossip, misremember and lie;
- now and then someone steals, crashes a car into a fence and drives on, or hurts someone;
- every clue, statement, mistake and lie in a case comes from that simulated history and can be traced back to
  it;
- the game makes cases from it on its own, and checks that each one can be solved before offering it.

**The game it produces is not fun enough.** The problems are in the gameplay format, not in the code:
- **Investigation feels like work rather than meaningful discovery.** A case holds about 500 statements, 85-90%
  of them unrelated to it. An automated investigator needs about 300 questions to reach the answer. A careful
  player spends most of their time sifting, not discovering.
- **Too much information, not enough rewarding detective play.** The decisive moment is usually a
  contradiction between a culprit's account and a record or two witnesses. It is found by patient
  cross-checking more than by insight, and it feels like bookkeeping when it comes.
- **Characters lack lasting identity and emotional attachment.** Residents have traits, faces, relationships
  and histories, but the player meets them as sources of statements. There is no time to care about them, and
  no reason to.
- **Cases reset relationships and personal histories.** Every case is a fresh town with fresh people. Nothing
  the player learns, nobody they come to know, and no consequence of their accusations carries over to the
  next case.

**Any revival should reconsider the core gameplay format before further implementation.** Adding content,
polish or more simulation detail to the present format would not address the reasons above. Questions worth
answering first, on paper or in a throwaway prototype:
- What is the player doing minute to minute, and what makes a single moment of it rewarding?
- How does the player get to know and care about a small cast over time (a persistent town, recurring
  characters, consequences that last)?
- How much of the simulated truth should ever reach the player, and through what? Fewer, richer, more
  deliberate clues rather than everything everyone remembers.
- Is the simulation the game, or the engine behind a more authored experience?

The simulation, the case pipeline and the solvability gate described below are likely to be worth reusing
whatever format is chosen.

## Where things stand

| | |
| --- | --- |
| Repository | `crosenlund79/ProjectMystery` |
| Working branch | `claude/godot-investigation`: all the Godot work. This document is its last commit. |
| Default branch | `claude/new-session-x75cqf`, at `2789ba2`: the original Python prototype (v0.1 and the Windows launchers) only. The working branch descends from it and is 63 commits ahead. It was never merged and there is no pull request; merging is a decision for later. |
| Last code commit | `4e2d047`. Later commits (`c65b434`, and the one adding this document) change documentation only. |
| CI | Green. Runs 60 and 61 passed on every job; the run for this document's commit is the last one. |
| Godot tests | 143 tests, 23,693 checks, all passing (Windows, CI run 60). |
| Python tests | 68 tests, all passing, 1 skipped (the skip is a Windows-only launcher test when run elsewhere). |
| Engine | Godot 4.3-stable (pinned in CI); Python 3.10+ with no dependencies for the laboratory. |

Build artifacts (the Windows game, the web build, screenshots, simulation demos) are attached to every CI run.
GitHub deletes them after 90 days, so a fresh run is needed to get a build after that.

## What exists and works

### The Godot game (`godot/`)

It needs no Python, no installer, no network and no accounts. The game data is embedded in the executable.

- **Menus:** New Case, Continue, Load Case (saved investigations, import a `.mcase` file), Settings (text size,
  high contrast, fullscreen, reset), and an opening scene shown once.
- **New Case:**
  - 15 bundled cases, made by the Python laboratory, with filters by difficulty;
  - the detective mode: Absolute Beginner, Hobby Detective or Experienced Detective;
  - **Generate Mystery…** (below).
- **The investigation:**
  - The town is a clickable map; you walk between places and meet whoever is there.
  - Talk to people face to face, with portraits that change expression. Ask by topic, press someone who
    holds back, ask for more, and ask "and before that?".
  - Look around places and examine vehicles. Private places need the owner's consent.
  - Read the record books where they are kept: the grocery ledger, the pub's tab book, the clinic log, the
    workshop's job book.
- **The tablet:**
  - case notes and the notebook, where everything heard is filed;
  - evidence; the people you have met;
  - a timeline that finds and explains contradictions;
  - hints, bought with credits;
  - the theory form.
- **Sorting evidence:** mark anything Suspicious, Active or Ignored.
  - Hobby Detectives may check a suspicious item: three wrong calls and the checks are gone.
  - Absolute Beginners get Detective's Intuition: a chime and the two entries that do not add up.
- **The reveal:** after a theory is submitted (or the player gives up), the sealed truth is opened. The player
  sees what really happened, a score, their notebook checked against the truth, and the leads they missed.
- **Saves:** after every action, under `%APPDATA%\ProjectMystery` on Windows. A save is never applied to a
  changed case.
- **Art:** template portraits, houses and places. All of them can be overridden with your own files
  (`godot/art/README.md`).

### The native simulation (`godot/scripts/sim/`, pilots 1-3B)

A full port of the Python simulation, compared with it by statistics (not event by event):
- **The town:** residents with needs, traits, jobs, money, debts and relationships, living hour by hour in a
  town with homes, a grocery, a pub, a mill, a clinic, a workshop, the square and Mill Road. Four seasons:
  normal, scarcity, crisis and tension.
- **Knowledge:** perception, memory (with forgetting and drifting times), gossip, misidentifications and
  suspicions.
- **Crime:** theft, hidden loot, bookkeeping mistakes, losses found, and traces. Also fights, injuries and
  rare deaths, drunken falls, collisions on Mill Road, the clinic, repairs, and people found hurt or missed.
- **Deterministic:** the same seed and settings give the same history on Windows and Linux. 26 histories are
  pinned (`godot/tests/sim_golden.json`).
- **One deliberate difference from Python:** grocery workers may serve themselves. This ends a deadlock in
  which a whole town stopped buying food.

### Native case generation (`godot/scripts/cases/`, pilots 4A-4B)

- **Extraction** (`case_builder.gd`, `case_text.gd`, `case_relevance.gd`):
  - each incident somebody discovered is frozen at the moment an investigator would arrive;
  - testimony comes from each resident's own beliefs, with their mistakes, loyalties, guarded and withheld
    knowledge, and lies only where the history gives a reason;
  - traces, records and consent come from what is really there;
  - the sealed truth is kept apart, and every statement, trace and record line is audited back to the history.
- **Suitability, hints and packaging** (`case_suitability.gd`, `case_package.gd`): the existing `.mcase`
  format, with the truth sealed and the per-item relevance verdicts sealed separately.
- **The solvability gate** (`case_solver.gd`, `case_generate.gd`):
  - Only a case with someone genuinely responsible for a crime is considered.
  - A truth-blind investigator plays the player's view through the real investigation engine, under the
    game's rules, and must name the right person, explanation and motive from evidence that was not mistaken.
  - Only then is the seal opened, to check the conclusion. Cases that fail are rejected with a reason. Nothing
    is added to a case to make it solvable.
- **Yield** (40 simulated months, CI run 57):
  - 106 candidates, 73 eligible, 16 playable, and no false accusation;
  - thefts 9 of 66, fights 3 of 3, collisions 4 of 4;
  - tension and scarcity seasons give most of them.
- **Generate Mystery** (`case_generation_job.gd`, `scripts/ui/generate_screen.gd`), in the New Case menu:
  - the player chooses the town size, the conditions, the number of days, an optional seed and how many
    towns to try;
  - towns are simulated a little each frame, with a progress bar, and can be cancelled;
  - other seeds are tried automatically, and a failure explains itself, with Retry or Back;
  - the first case that passes the gate is saved and offered: Investigate, Generate Another, or Case Library;
  - generated cases sit in the library beside the bundled and imported ones, and play, save and reveal like
    them.

### The Python laboratory (`mystery/`)

The original prototype, kept as the reference implementation:
- the simulation, case export and suitability;
- the text version of the game;
- batch diagnostics;
- the builder of the bundled library;
- Windows double-click launchers (`Play-Mystery.cmd`, `Mystery-Lab.cmd`).

The Godot game does not need it. CI uses it to regenerate the bundled library and the reference statistics, and
to read the Godot-made case files as a cross-check.

## Running, testing and building

**Play the Windows build:** open the latest green CI run on `claude/godot-investigation`, download the
`ProjectMystery-windows` artifact, extract it, and run `ProjectMystery.exe`. It is not code-signed, so choose
*More info → Run anyway* if SmartScreen asks.

**From source:** open `godot/project.godot` in Godot 4.3 and press F5.

**Godot tests** (about 7-8 minutes on the CI Windows machine):

```bash
godot --headless --path godot -s res://tests/run_tests.gd
```

**Headless simulation and generation demos** (see `docs/godot-simulation-migration.md`, *Running it*):

```bash
godot --headless --path godot -s res://tests/run_sim.gd -- --seed=1 --days=30 --profile=tension --crime --cases
```

```bash
godot --headless --path godot -s res://tests/run_sim.gd -- --seed=2 --days=30 --profile=tension --generate --golden
```

**Python laboratory tests:**

```bash
python -m unittest discover -s tests -t .
```

**Windows export:**
- CI does it on every push (`.github/workflows/ci.yml`, job *Godot game*): it imports the project, runs the
  tests, exports, runs the executable's smoke test, and uploads the build.
- Locally: install the Godot 4.3 export templates, then *Project → Export → Windows Desktop*.

## Known bugs, gameplay issues and unfinished work

**Gameplay** (the reasons for parking, plus):
- **Implausible alibis.** In 12 of 16 playable generated cases, the culprit's false account has them standing
  in the street or the square for 2 to 13 hours. A player can suspect them from that alone.
- **Excessive irrelevant testimony.** About 500 statements a case, 85-90% unrelated (up to 97%).
- **Every guilty driver tells the same lie** ("Hit a deer out on the ridge road"), so every collision is solved
  the same way.
- **Low yield in quiet seasons.** In 10 normal months, 1 playable case. Thefts are mostly unsolvable, because
  nobody sees anything and the thief's account is never caught out.
- **Time stands still** during an investigation: nobody moves around town while you investigate.
- **No human playtesting.** All verification is automated. Pacing, difficulty labels and wording have never
  been tried on real players.

**Simulation realism** (inherited from the Python rules, documented in `docs/godot-simulation-migration.md`,
*Realism concerns*):
- someone badly hurt on Mill Road at night whom nobody passes still gets home at 10:00;
- untreated injuries never get worse;
- deaths are very rare;
- "home around 18:15 and to bed" is said of any long evening at home.

**Technical:**
- **Harmless error lines.** `test_memory` prints two "unsupported format character" error lines in the Godot
  test log. They are pre-existing, and no test fails because of them.
- **Slow library refresh.** The case library reads and validates every case file in the player's folder in
  full each time it refreshes. With many generated cases, opening New Case would slow down.
- **Generated cases cannot be deleted in the game.** Remove their `.mcase` files from the `cases` folder by
  hand.
- **Duration of a default request.** With the default settings (60 days, up to 12 towns), a generation request
  was not timed in CI; tests used shorter settings. Each town takes a few seconds, so a default request can
  take a minute or two. The longest single step measured was about 0.2 s.
- **The seal deters accidental spoilers only.** It is not security.
- **Pinned versions:**
  - Godot is pinned at 4.3. Moving to a newer version needs a re-run of every pinned digest, and possibly
    re-pinning (`sim_golden.json`, `case_golden.json`).
  - The bundled library is still made by Python (`godot/cases/`), and seeds stay valid only for the versions
    that made them.

**Documentation that predates the last pilots** (left as written):
- `docs/godot-migration.md`, *Known limitations*: says new towns are generated only in Python. Godot generates
  them too since pilot 4B.
- `docs/godot-migration.md`, *Porting the simulation later*: plans a byte-identical port with Python's random
  streams. The port that was done compares the two by statistics instead.
- `README.md` once calls the Experienced mode "Normal Detective" (its earlier name).

**Unfinished, by plan:**
- difficulty redesign and custom generation settings (the iteration that was to come next);
- the recommendations in `docs/godot-simulation-migration.md`, *Next after pilot 4B*: believable false
  accounts, more ways for honest townspeople to notice things, less noise in testimony, and varied stories
  from guilty drivers.

## Documentation map

| Document | What it covers |
| --- | --- |
| `README.md` | Playing, the laboratory's commands, how it works, the repository map. |
| `docs/concept.md` | The original concept: pillars, the two-stage experience, the incident engine, solvability, the research program, open questions. Read it before rethinking the format. |
| `docs/prototype-notes.md` | What the first Python prototype measured and taught. |
| `docs/godot-migration.md` | The Godot game: layers, the town and the tablet, data flow, rule parity with Python, building. |
| `docs/investigation-rules.md` | The investigation rules shared by Python and Godot: questioning, looking around, evidence management, intuition, hints, timeline, scoring. |
| `docs/case-format.md` | The `.mcase` package: the player-safe view, the sealed truth, relevance seals, compatibility. |
| `docs/godot-simulation-migration.md` | The native simulation and case generation, pilot by pilot: modules, determinism, verification, results, differences from Python, realism concerns, the Generate Mystery menu, and next steps. |
| `godot/scripts/sim/README.md` | A short map of the simulation scripts. |
| `godot/art/README.md` | Replacing the art. |

## Where to resume

1. **Decide the format first.** Read the reasons for parking above and `docs/concept.md`, and settle what the
   player does and why it is rewarding. Prototype that cheaply, before touching this code.
2. **Then reuse what fits.** The parts most likely to survive a new format, from the most self-contained:
   - `godot/scripts/sim/`, a deterministic town with knowledge, gossip and crime;
   - `godot/scripts/cases/`, which turns a history into a case, judges it without the truth, and seals it;
   - `godot/scripts/core/investigation.gd`, the rules engine;
   - the test suites in `godot/tests/`, which pin all of the above.
3. **Before changing anything,** run the Godot and Python tests and a CI run, to confirm the baseline still
   holds.
4. **Branches.** If work resumes in this repository, decide whether `claude/godot-investigation` should be
   merged into the default branch.
