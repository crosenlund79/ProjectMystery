# Moving the town simulation to Godot

The goal is a self-contained Godot 4 game in which the town simulation, case generation and the investigation
all run natively, with Python retired from the active architecture. This document covers two pilots:

- **Pilot 1:** residents living in a town.
- **Pilot 2:** what they see, hear, remember and tell each other.

The existing game is unchanged: cases are made by Python and played in Godot.

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

## What pilot 2 adds: perception, memory and gossip

The event log stays the truth. Every resident also has a memory of **beliefs**, kept apart from the truth.

**What a belief holds:**
- a claim (what, who, with whom, where, when, a detail);
- where it came from, its *source*: `self`, `saw`, `heard`, `told` or `inferred`;
- when it was acquired;
- how sure the holder is;
- how much it matters to them;
- its provenance:
  - the event it was perceived from, or the chat it was heard in;
  - who told them, and the teller's own belief it was copied from;
  - for an inference, the beliefs it was drawn from.

A belief is never read back from the truth once it has formed. A mistake made along the way (`misidentified`,
`time_distorted`, `certainty_inflated`) is recorded for developers only; the resident does not know.

| Python (`mystery/`) | Godot (`godot/scripts/sim/`) | Notes |
| --- | --- | --- |
| `sim/memory.py` | `sim_memory.gd` | Claims, beliefs, each resident's memory, and the source ranking (hearsay never replaces something seen). Salience for 31 kinds of claim. Forgetting: a belief is kept for 1.5 + 25 x salience days, and less certainly as time passes; anything with salience 0.9 or more is never forgotten; things near an incident the holder knows of stay. Recollection: 30% of the time a remembered time slips by 30-60 minutes. |
| `sim/engine.py` (`broadcast`, co-presence, doorways, sightings) | `sim_perception.gd` | **Seeing:** people at the place, awake, see an event. **Hearing:** people asleep there, or near enough for how loud it was, hear it. They recognise a voice they know well. **Co-presence:** at the end of each hour, people notice who is with them. **Doorways:** housemates notice comings and goings, or hear the door in their sleep. **Transit:** people out see others pass on the square and Mill Road. **Recognition:** 97% normally. Outdoors after dark it depends on how well they know the person. It is worse from a moving vehicle and after drink. A failed recognition is a wrong guess 22% of the time, and that guess falls on someone the observer already resents. |
| `sim/actions.py` (`chat`, `conceals`, `pick_gossip`, `tell`, `infer_suspicions`) | `sim_gossip.gd` | **What is shared:** in a chat, each speaker passes on their freshest, most salient item, and a second one with a chance equal to their sociability. They never tell the listener about the listener's own troubles. They never tell anything that could hurt someone they love (loyalty at affection 0.75 or more). **How sure the listener is:** confidence becomes the speaker's confidence x (0.55 + 0.35 x trust in the speaker). **Distortions:** a hedged "I think it was ..." can lose its hedge, and a time can drift by 30-60 minutes. **Provenance:** a told belief stays `told` however often it is passed on. **Suspicion:** inferred from a loss or damage the resident knows of, plus what they themselves saw or heard nearby, plus their grudges. |
| the belief parts of `actions.py` and `engine.py` | `sim_actions.gd`, `simulation.gd`, `sim_decisions.gd` | The same events create the same beliefs: the town's history (grudges and debts, told to some at the start), credit and refusals, loans and refusals, repayments, help, reconciliation, arguments (seen there, heard as raised voices next door), missed rent, layoffs and overdue debts. Decisions read only what the decider believes. |

**Decisions that now depend on memory, as in Python:**
- **Financial help:** offered to someone the helper has heard is struggling.
- **Lending caution:** a lender's chance of lending drops by 0.25 for each unpaid debt of the borrower's they *know of*; debts they have not heard of do not count.
- **Confrontations:** a resident with a stake confronts the person they suspect. The accused is then told why and resents it.

Pilot 1 had one stand-in for this, "the person who refused a loan knows the asker is struggling". With memory
on, that comes from beliefs instead.

The configuration switch `"memory": false` turns pilot 2 off and runs pilot 1 exactly. Its pinned histories
are unchanged (see Determinism).

## What waits for later pilots

These are the boundaries. Each later layer plugs into the event log, presence intervals, debts, records, money
transfers and beliefs that pilots 1 and 2 already keep.

- **Crime and incidents** (`sim/incidents.py` and the crime half of `actions.py`): theft, assault, falls,
  collisions, ledger errors, discovery, hiding loot, injuries, the clinic, repairs.
  - An argument that would turn violent ends with the argument logged and counted as `escalations_deferred`.
  - The suspicion pipeline is in place and tested, but stays dormant until something is lost or damaged.
  - See [Next: pilot 3](#next-pilot-3-crime-and-incidents).
- **Evidence, testimony export, suitability and case packaging** (`mystery/cases`).
- **The investigation rules** already run in Godot (`scripts/core/`) and are untouched.

## Determinism

Every random draw comes from a named stream seeded from the run seed, the same way as in Python. There is no
global random generator, no iteration over unordered collections and no transcendental function. Running the
same seed and settings twice gives an identical event-log digest; the tests check this, and CI compares the
digests produced on Windows and Linux.

Six histories are pinned in `godot/tests/sim_golden.json`. Both the Windows tests and the Linux demo must
reproduce them:

- **Memory off:** Pilot 1's three histories (seed 7 normal, seed 21 tension, seed 5 crisis with 12
  residents). Their digests were pinned before memory existed and are byte-for-byte unchanged by Pilot 2. This
  is the separate validation of the digest change: with the new layer switched off, nothing else moved.
- **Memory on:** the same three runs with perception, memory and gossip. Their histories differ because gossip
  happens in chats, beliefs steer decisions, and the extra random draws shift later ones. They were pinned
  from the Windows run of commit 8d67289 and reproduced on Linux in CI run 29.

Python's random numbers are not reproduced. The two simulations follow the same rules with different random
draws, so they are compared by their statistics, not event by event.

## Running it

```bash
godot --headless --path godot -s res://tests/run_sim.gd -- --seed=7 --days=14 --profile=normal --out=sim-demo
```

**What it prints:**
- the town and its people;
- the first day, hour by hour, and a line per day after that;
- everyone's state at the end;
- what the town believes, by source and by mistake;
- how the most widely known piece of news got round, person by person, with who told whom and when;
- one misidentification and one drifted rumour, each set against the truth;
- how much one resident has forgotten of Day 1;
- the integrity checks and the event-log digest.

**Options:**
- `--out=<folder>` writes the whole history as JSON, beliefs included.
- `--golden` checks the six pinned digests.
- `--memory=off` runs pilot 1.

CI runs it on Linux and uploads the result as the `simulation-demo` artifact.

```gdscript
var sim = preload("res://scripts/sim/simulation.gd").new({"seed": 7, "days": 30, "profile": "tension"}).run()
for ev in sim.events.events:
    print(ev["time"], " ", ev["summary"])
for b in sim.memory[sim.ids[0]].beliefs:
    print(b["source"], " ", b["claim"]["kind"], " ", b["confidence"])
```

## How it is verified

`godot/tests/test_sim.gd` and `godot/tests/test_memory.gd` are part of the Godot test run in CI.

### The world (pilot 1, and still with memory on)

- **Reproducible.**
  - The same seed and settings give the same event log, money, whereabouts and debts.
  - A run stopped after three days and continued is identical to one run straight through.
  - Another seed, season or town size gives another history.
  - The six pinned histories are reproduced on Windows (the tests) and Linux (the demo).
- **Integrity**, on 12 runs of 30 days (4 seasons, 3 seeds):
  - Every transfer replayed from the starting balances ends exactly at the final balances and never goes below zero.
  - Cash and food are conserved, apart from what enters from or leaves to the outside world.
  - Every till, tin and pantry holds what its owners expect.
  - Every event is in time order, at a real place, with real people, after its causes.
  - Every walk follows the map, and everyone's whereabouts are continuous.
  - Needs stay within 0-100; nobody sleeps away from home; every settled debt has its repayment.
- **Daily life.**
  - Everyone eats, and everyone with a wage is paid.
  - Shops and the mill stay shut on Sundays.
  - People move, shop, drink, deposit savings, talk and pay rent.

### Knowledge (pilot 2)

**Provenance**, checked for every belief of every run (`sim_check.gd`, the same 12 runs). No resident holds
anything without a plausible source:

| Source | The belief is accepted only if ... |
| --- | --- |
| `self` | the holder took part in the event. |
| `saw` | the holder was, by the presence record, at the claim's place or the event's place at that minute. |
| `heard` | the holder was within earshot (hops on the map, up to the event's audibility less one); a footstep or door is heard only in the same place. |
| `told` | the teller held the belief it was copied from, acquired it earlier, and a chat or argument between the two took place at that minute. The claim is unchanged apart from the documented distortions (time, hedging). For the town's history, the teller was a party to the original grudge or debt. |
| `inferred` | every premise is a belief the same resident already held. |

Errors only arise where they can: a misidentification only for an eye or ear witness (or passed on by
telling), a drifted time or lost hedge only in the telling. A sighting of someone passing is checked against
who really passed: with no error it must name them, and marked misidentified it must name someone else.

**Scenarios** (`test_memory.gd`):

| Test | What it shows |
| --- | --- |
| Forgetting | A passing presence is remembered after a day, less surely after four, and gone after four and a half, unless it was near an incident the holder knows of. A debt is never forgotten and never misremembered. About 30% of old sightings come back 30-60 minutes off. |
| Sight and hearing | An argument is seen by everyone awake in the room, woken to by about half the sleepers there, and heard next door as a noise (not who argued about what). Nobody two or more places away learns of it, and the parties are not counted as witnesses of their own argument. |
| Recognition | Indoors by day people are recognised (over 93%); a stranger on the dark square mostly is not. A misidentification always names someone else, and that name falls on someone the observer dislikes well above chance (more than a third of wrong guesses, against 1 in 8 by chance). |
| Gossip | News comes up in a chat; a speaker keeps the troubles of someone they are fond of to themselves; nobody is told of their own hardship; news more than four days old is not passed on; a speaker remembers whom they told and does not tell them again. |
| Telling | A told belief is `told`, names the teller and the teller's belief it was copied from, and is trusted as far as the teller is. Being told what you saw yourself leaves it as seen. A hedged sighting sometimes loses its hedge and a time sometimes drifts; otherwise it is passed on as it was. |
| Lending caution | A debt the lender never heard of changes nothing; one known unpaid debt takes 0.25 off the chance; hearing it was repaid restores it; with memory off nothing is known. |
| Help from hearsay | Someone told that a friend is struggling may help; without being told, they never do. |
| Suspicion | From a staged loss at a till, a sighting nearby and knowledge of the suspect's hardship, the till's owner infers one suspicion (source `inferred`, with those three premises recorded), has a stake, and goes to confront. Afterwards the accused holds the accusation as `told`, by the owner, copied from the owner's suspicion. |
| Whole months | Over 30-day runs: no provenance problems; news is passed on by people who were themselves told; misidentifications and drifting times happen; the first person to know of an argument always took part in it, saw it or heard it. |

### Compared with Python

`tools/sim_reference.py` runs the Python simulation with its crime layer off (40 runs: 4 seasons x 10 seeds).
It measures that simulation exactly as `sim_check.gd` measures the Godot one:

- 20 kinds of event per resident per day;
- where people spend their hours, sleep, needs, money and open debts;
- since pilot 2, memory:
  - beliefs by source, by kind and by error, per resident per day;
  - gossip chats and items passed on;
  - suspicions;
  - for each argument, refusal and missed rent, how many people *not involved* came to know of it;
  - the share of loan requests granted.

**What the test enforces:**
- Routine and core memory statistics must match within tolerance: beliefs seen and told, gossip chats and items passed on.
- The rest are reported.
- In CI run 29, all 260 statistics (65 per season) were within tolerance.

## Results (CI run 29)

Godot: 3 seeds per season, 30 days. Python: 10 seeds. Per resident per day unless stated.

**Gossip and knowledge**

| Season | Gossip chats | Items passed on | Told beliefs | Seen beliefs | Others who learn of an argument | ... of a refusal | ... of missed rent |
| --- | --- | --- | --- | --- | --- | --- | --- |
| normal | 0.96 / 1.26 | 2.13 / 3.10 | 0.82 / 1.35 | 9.2 / 8.1 | 6.2 / 4.9 | 6.2 / 4.7 | 6.1 / 4.5 |
| scarcity | 1.53 / 1.52 | 4.18 / 3.82 | 1.65 / 1.73 | 11.1 / 9.5 | 6.5 / 5.7 | 3.7 / 4.0 | 2.6 / 3.3 |
| crisis | 1.47 / 1.71 | 3.77 / 4.71 | 1.82 / 2.09 | 10.1 / 12.5 | 4.4 / 5.6 | 3.0 / 3.6 | 2.1 / 2.1 |
| tension | 1.92 / 1.86 | 5.60 / 5.32 | 2.13 / 1.99 | 16.5 / 18.2 | 7.1 / 6.2 | 4.4 / 3.9 | 1.6 / 1.7 |

(Godot / Python in each cell.)

**Lending and help**

| Season | Loans granted | Loans refused | Share of requests granted | Help given | Mistaken identities | Rumours with a drifted time |
| --- | --- | --- | --- | --- | --- | --- |
| normal | 0.006 / 0.010 | 0.019 / 0.034 | 0.16 / 0.24 | 0.001 / 0.006 | 0.11 / 0.09 | 0.21 / 0.39 |
| scarcity | 0.006 / 0.011 | 0.094 / 0.069 | 0.06 / 0.16 | 0.004 / 0.011 | 0.12 / 0.09 | 0.50 / 0.55 |
| crisis | 0.017 / 0.018 | 0.168 / 0.151 | 0.11 / 0.10 | 0.007 / 0.006 | 0.11 / 0.15 | 0.43 / 0.64 |
| tension | 0.022 / 0.019 | 0.128 / 0.130 | 0.13 / 0.14 | 0.006 / 0.010 | 0.21 / 0.24 | 0.60 / 0.56 |

**Routine** (unchanged in character from pilot 1):

| Season | Godot: asleep / home / work / meals / wages | Python: asleep / home / work / meals / wages |
| --- | --- | --- |
| normal | 0.345 / 0.609 / 0.298 / 1.909 / 0.589 | 0.344 / 0.623 / 0.300 / 1.920 / 0.587 |
| scarcity | 0.344 / 0.598 / 0.302 / 1.873 / 0.581 | 0.345 / 0.618 / 0.298 / 1.896 / 0.585 |
| crisis | 0.347 / 0.644 / 0.271 / 1.892 / 0.487 | 0.344 / 0.602 / 0.261 / 1.510 / 0.431 |
| tension | 0.345 / 0.570 / 0.300 / 1.876 / 0.590 | 0.344 / 0.559 / 0.300 / 1.868 / 0.582 |

**Speed:**
- 30 simulated days with memory take 0.56-0.97 s on the Windows CI runner (pilot 1: 0.55-0.78 s).
- 14 days take 0.35 s on Linux (pilot 1: 0.23 s).

## Known differences from Python

All are within the test tolerance.

| Difference | Godot | Python | Why |
| --- | --- | --- | --- |
| Suspicions, accusations over them, `inferred` and `suspect` beliefs | none | 0.06-0.09 suspicions a day | Every Python suspicion in these runs comes from a ledger mistake (1.5% x (1 - the clerk's diligence) of sales) that shows up later as a loss. Ledger mistakes belong to the incident layer (pilot 3). The Godot pipeline is the same and is tested with a staged loss. |
| Lending in the normal and scarcity seasons | 6-16% of requests granted | 16-24% | Godot ends those seasons with more open debts (scarcity: 13 against 8.5, from pilot 1's slightly higher credit), and a lender's chance drops by 0.25 for each one they know of. In crisis and tension the shares match (0.11 / 0.10, 0.13 / 0.14). Worth watching once pilot 3 settles the debt totals. |
| Help given | 0.001-0.007 | 0.006-0.011 | Rare on both sides (Python 2-3 a month in a town of 10, Godot 0.3-2), so three Godot seeds are a small sample. In pilot 1 it was 0.000-0.003; with gossip, the gap closed in crisis and tension. |
| How far news of a refusal or missed rent spreads, normal season | 6.1-6.2 others | 4.5-4.7 | Godot's normal season has fewer refusals (0.03 a day against 0.05), so each is talked about more. In the other seasons the spread matches. |
| Fewer gossip chats in the normal season | 0.96 | 1.26 | Follows from the line above: less news to pass on. |
| Seeing people drunk (scarcity, crisis) | 0.94, 0.41 | 0.46, 0.22 | Follows from pilot 1's higher drink count in those seasons. |
| An argument that would turn violent | the argument is logged, the fight is not | a fight (assault), with injuries | Crime layer. Counted as `escalations_deferred`. |
| Ledger mistakes | none | about 1 in 130 sales | Incident generation (pilot 3). |
| Meals in the crisis season | 1.89 | 1.51 | From pilot 1: Python's crisis runs vary widely (hunger standard deviation 18). |
| Chats | every chat is counted | only chats that pass on gossip are logged | Since pilot 2, Godot also logs only gossip chats; the comparison counts every chat on both sides. |

**Limitations of pilot 2:**
- **Dormant suspicion pipeline.** Suspicion inference, a resident's stake in an incident, accusations, and the "nearby sightings become worth mentioning after an incident" rule all run in every simulation. They have nothing to work on until pilot 3 creates losses and damage. The scenario tests exercise them with a staged loss, so they are known to work.
- **Kinds of belief not yet produced.** The memory model holds every Python kind, but nothing creates the incident kinds yet: loss, damage, injury, struck, fall, death, missing, confession, stash, theft_self, collision_self, vehicle_damage, repair, treated. Concealment of one's own theft or collision is ported but unused.
- **The town's history is told once, at the start.** Old grudges and debts are known to their parties, and told to some others on Day 1 at minute 0, as in Python. The told beliefs point at the history record, not at a chat.
- **Developer-only provenance.** Beliefs are not yet visible in the game, which still plays Python-made cases. Exporting testimony from beliefs belongs to the case-packaging pilot.

## Next: pilot 3, crime and incidents

**Recommended scope.** Port the crime half of the Python simulation: about 900 lines of Python, against Pilot 2's 550 lines of new GDScript modules.
- `actions.py` lines 522-1095:
  - theft: `steal`, `hide_loot`, `loss_discovered`;
  - violence: `assault`, `injure`, `kill`;
  - accidents: `check_collision`, `check_fall`;
  - discovery: `notice`, `notice_injury`, `found`;
  - aftermath: `tidy`, `clinic`, `repair`;
  - confession: `_confess`.
- `decisions._steal_intent`.
- The evidence, missing-person and incident parts of `engine.py` (`_notice_evidence`, `_tidy_evidence`, missed people, the incidents registry).
- The ledger mistakes in `actions.py`.
- `incidents.py`.

**A configuration switch.** Add `"crime"`, off by default until the pilot is accepted, so the six pinned
histories stay reproducible. Then pin crime-on histories next to them.

**Suggested order:** two halves, each reviewable on its own.

**Pilot 3a: theft and money.**
- Ledger mistakes.
- Stealing from tills, stock and household savings.
- Hiding loot and the stash.
- Loss discovery at counting time.
- Evidence and traces left at the scene, with noticing and tidying.
- The incidents registry.

This wakes up pilot 2's suspicion pipeline, should close the suspicion difference above, and gives the case
pipeline its most common incident.

**Pilot 3b: violence and accidents.**
- Assault replaces `escalations_deferred`.
- Injuries and the clinic.
- Falls after drink, and collisions on Mill Road.
- Vehicle damage and repairs.
- People found or missed.
- Death (rare) and confessions.

**Verification, in the same style as pilots 1 and 2:**
- **Python reference.** Regenerate it with the crime layer **on**. Compare incident rates per season (thefts, losses discovered, assaults, injuries, falls, collisions), suspicions and accusations, and how many people come to know of each incident.
- **Provenance.** Extend the checks to the incident kinds:
  - nobody knows of a theft without seeing it, discovering the loss, being told, or inferring it from what they hold;
  - a culprit's own knowledge is `self` and concealed;
  - an injury is known by those who saw it, treated it or were told.
- **Integrity.** Stolen money and goods stay conserved: in the thief's hands, in a stash, or spent. Every injury has a cause. Every repair has damage before it.
- **Untouched.** Testimony export, suitability, case packaging, difficulty and the UI stay out of scope. They are the pilot after that.
