# Moving the town simulation to Godot

Goal: a self-contained Godot 4 game in which the town simulation, case generation and the investigation all
run natively, with Python retired from the active architecture. This document covers **pilot 1**: residents
living in a town. The existing game (cases made by Python, played in Godot) is unchanged.

## What pilot 1 contains

| Python (`mystery/`) | Godot (`godot/scripts/sim/`) | Notes |
| --- | --- | --- |
| `rng.py` | `sim_rng.gd` | SHA-256-derived seeds per labelled stream, like `derive_seed`. Integer and exact arithmetic only, so a seed gives the same history on every platform. |
| `sim/clock.py` | `sim_clock.gd` | Minutes since Day 1 00:00, one-hour ticks, Day 1 a Monday, Sunday a rest day. |
| `sim/config.py` | `sim_config.gd` | The four seasons and every price, unchanged. |
| `sim/world.py` (places, containers, vehicles, books, debts, transfers) | `sim_world.gd` | The same town map, walking times, containers and books. Evidence is left out. |
| `sim/residents.py` | `sim_resident.gd`, `sim_town.gd` | The same roles, wages, starting cash, traits, households, relationships, grudges and starting debts. |
| `sim/decisions.py` | `sim_decisions.gd` | The same utility scores, noise and tie-breaking for every lawful choice. |
| `sim/actions.py` (daily life, the economy, interactions) | `sim_actions.gd` | Work, meals, shopping, credit, drinking, socialising, odd jobs, loans, repayments, help, reconciliation, confrontations, chats, closing time, wages, takings. |
| `sim/engine.py` (tick loop, needs, money, movement) | `simulation.gd` | The same phases: needs, scheduled duties (rent, deliveries, layoffs, morning cash), decisions, movement, actions, closing time. |
| `sim/events.py` | `sim_events.gd` | Append-only log with causes and a SHA-256 digest. |
| (tests) | `sim_check.gd`, `tests/test_sim.gd`, `tests/run_sim.gd` | Integrity checks, statistics, the headless demo. |

## What waits for later pilots

These are the boundaries. Each later layer plugs into the event log, the presence intervals, debts, records
and money transfers that pilot 1 already keeps.

- **Perception and memory** (`sim/memory.py`, the belief parts of `engine.py` and `actions.py`): sightings,
  hearing, misidentification, gossip, forgetting. Pilot 1 keeps one piece of knowledge, which needs no
  memory model: the person who refuses a loan or credit knows the asker is struggling.
- **Crime and incidents** (`sim/incidents.py`, theft, assault, falls, collisions, ledger errors, discovery,
  hiding loot, injuries, the clinic, repairs). In pilot 1 an argument that would turn violent ends with the
  argument logged and counted as `escalations_deferred`.
- **Evidence, testimony export, suitability and case packaging** (`mystery/cases`).
- **The investigation rules** already run in Godot (`scripts/core/`) and are untouched.

## Determinism

Every random draw comes from a named stream seeded from the run seed, the same way as in Python. No global
random generator, no iteration over unordered collections, no transcendental functions. Running the same
seed and settings twice gives an identical event log digest; the tests check this, and CI compares the
digests produced on Windows and Linux.

Python's random numbers are not reproduced: the two simulations follow the same rules with different random
draws, so they are compared by their statistics, not event by event.

## Running it

```bash
godot --headless --path godot -s res://tests/run_sim.gd -- --seed=7 --days=14 --profile=normal --out=sim-demo
```

It prints the town and its people, the first day hour by hour, a line per day, everyone's state at the end,
the integrity checks and the event-log digest, and writes the whole history as JSON (`--golden` also checks
the pinned digests). CI runs it on Linux and uploads the result as the `simulation-demo` artifact.

```gdscript
var sim = preload("res://scripts/sim/simulation.gd").new({"seed": 7, "days": 30, "profile": "tension"}).run()
for ev in sim.events.events:
    print(ev["time"], " ", ev["summary"])
```

## How it is verified

`godot/tests/test_sim.gd`, part of the Godot test run in CI:

- **Reproducible.** The same seed and settings give the same event log, money, whereabouts and debts; a run
  stopped after three days and continued is identical to one run straight through; another seed, season or
  town size gives another history. Three histories are pinned by digest (`tests/sim_golden.json`) and
  reproduced on Windows (the tests) and Linux (the demo).
- **Integrity**, on 12 runs of 30 days (4 seasons, 3 seeds): every transfer replayed from the starting
  balances ends exactly at the final balances and never goes below zero; cash and food are conserved apart
  from what enters from or leaves to the outside world; every till, tin and pantry holds what its owners
  expect; every event is in time order, at a real place, with real people, after its causes; every walk
  follows the map; everyone's whereabouts are continuous; needs stay within 0-100; nobody sleeps away from
  home; every settled debt has its repayment.
- **Daily life.** Everyone eats; everyone with a wage is paid; shops and the mill stay shut on Sundays;
  people move, shop, drink, deposit savings, talk and pay rent.
- **Compared with Python.** `tools/sim_reference.py` runs the Python simulation with its crime layer off (40
  runs) and measures it exactly as `sim_check.gd` measures the Godot one: 20 kinds of event per resident
  per day, where people spend their hours, sleep, needs, money and open debts. The routine statistics must
  match within tolerance; the rest are reported.

## Known differences from Python

From CI run 26 (Godot: 3 seeds per season; Python: 10). All are within the test tolerance.

| Difference | Godot | Python | Why |
| --- | --- | --- | --- |
| Help given to someone struggling (per resident per day) | 0.000-0.003 | 0.006-0.011 | Only the person who refused a loan or credit knows of the hardship; in Python, gossip spreads it. |
| Loans granted (tension season) | 0.040 | 0.019 | Python's lenders hold back when they have heard of the borrower's other debts (memory). |
| Repayments | 0.026-0.059 | 0.033-0.040 | Follows from the loans. |
| Meals in the crisis season | 1.89 | 1.51 | Python's crisis runs vary widely (hunger standard deviation 18), and its lenders refuse more for the reason above. |
| Drinks in the scarcity season | 1.50 | 1.00 | Within the spread of the Python runs (standard deviation 0.36); worth watching. |
| Chats | every chat is logged | only chats that pass on gossip are logged | No gossip yet. The comparison counts every chat on both sides: 1.7-2.2 against 1.9-2.0 a day. |
| An argument that would turn violent | the argument is logged, the fight is not | a fight (assault), with injuries | Crime layer. Counted as `escalations_deferred`. |
| Confronting someone over a suspicion | never | sometimes | Needs memory (suspicions are inferred beliefs). |
| Ledger mistakes | none | 1.5% x (1 - the clerk's diligence) of sales, about 1 in 130 | Incident generation (a later pilot). |

Some of the comparison numbers (CI run 26):

| Season | Godot: asleep / home / work / meals / wages | Python: asleep / home / work / meals / wages |
| --- | --- | --- |
| normal | 0.345 / 0.614 / 0.301 / 1.920 / 0.597 | 0.344 / 0.623 / 0.300 / 1.920 / 0.587 |
| scarcity | 0.343 / 0.591 / 0.300 / 1.864 / 0.590 | 0.345 / 0.618 / 0.298 / 1.896 / 0.585 |
| crisis | 0.348 / 0.641 / 0.272 / 1.888 / 0.491 | 0.344 / 0.602 / 0.261 / 1.510 / 0.431 |
| tension | 0.346 / 0.571 / 0.300 / 1.904 / 0.584 | 0.344 / 0.559 / 0.300 / 1.868 / 0.582 |

Speed: 30 simulated days take 0.55-0.78 s on the Windows CI runner and 14 days 0.23 s on Linux.
