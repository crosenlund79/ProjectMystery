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
