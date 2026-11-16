# Moving the town simulation to Godot

The goal is a self-contained Godot 4 game in which the town simulation, case generation and the investigation
all run natively, with Python retired from the active architecture. This document covers three pilots:

- **Pilot 1:** residents living in a town.
- **Pilot 2:** what they see, hear, remember and tell each other.
- **Pilot 3A:** theft and financial incidents: who steals, how it is hidden, how it is found, what traces it
  leaves, and whom the town suspects.

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

## What pilot 3A adds: theft and financial incidents

Everything here runs only with the configuration switch `"crime": true`. It is off by default, so with it off
the town lives exactly as before: all six Pilot 1 and 2 histories are reproduced unchanged. Crime needs memory
(who finds a loss, whom they suspect, what a thief keeps quiet about), so `"crime": true` with `"memory": false`
is refused.

| Python (`mystery/`) | Godot (`godot/scripts/sim/`) | What it does |
| --- | --- | --- |
| `sim/decisions.py` (`_steal_intent`) | `sim_decisions.gd` (`_steal_intent`) | **Motive and opportunity.** Stealing is one more option, scored against every lawful one. It appears only when money pressure is at least 0.5 (or the resident is hungry, with an empty pantry and an empty purse), honesty is under 0.72, and drive outweighs morals, caution and the fear of doing it again. The opportunity depends on the hour: a business till in the dead of night (23:00-03:00), the grocery's stock if hungry, or by day (10:00-15:00, not Sunday) a house whose people are all at work. Spite for the owners makes a target more tempting. |
| `sim/actions.py` (`steal`) | `sim_crime.gd` (`steal`) | **Theft.** The thief gives up if anyone else is there; a cautious thief may give up at a locked door. Otherwise a locked door is forced, which leaves a trace and makes a noise heard next door. Half to nine tenths of the money is taken (or 8-16 units of stock), into the thief's own hidden stash. The theft is done discreetly: even someone there would not see it. It is registered as an incident with the thief responsible and a motive (money trouble, or a grudge). |
| `sim/actions.py` (`hide_loot`), `sim/engine.py` (`_morning_cash`) | `sim_crime.gd` (`hide_loot`), `simulation.gd` (`_morning_cash`) | **Concealment and the loot afterwards.** Back home, the thief hides the loot, which is a trace at their house. Stolen food goes into their pantry. Later, short of money, they quietly spend from the stash before touching the household tin. |
| `sim/actions.py` (ledger mistake in `shop`) | `sim_crime.gd` (`ledger_error`) | **Ledger mistakes.** On 1.5% x (1 - diligence) of sales, the clerk writes the sale in twice: the books expect money that never came in. This is an accounting incident with nobody responsible. |
| `sim/engine.py` (`count_container`), `sim/actions.py` (`loss_discovered`) | `simulation.gd` (`count_container`), `sim_crime.gd` (`loss_discovered`) | **Discovery.** Tills and stock are counted at opening and closing; a household tin is opened when someone puts money in or takes it out. A shortfall of 5 crowns or 3 units is noticed; anything smaller is put down to miscounting and written off. The counter knows, anyone there sees, and gossip does the rest. The incidents behind the shortfall are now discovered, with the window it happened in. |
| `sim/engine.py` (`_notice_evidence`, `_tidy_evidence`, `made_by`), `sim/actions.py` (`notice`, `tidy`) | `sim_crime.gd` (`notice_evidence`, `notice`, `tidy_evidence`, `tidy`, `made_by`) | **Traces.** A forced door is seen first by whoever opens up, and by passers-by: three in four by day, about one in three after dark. After 30 hours, the first person there by daylight mends it. A hidden stash is only ever found by someone who searches, which is the investigation, not the simulation. |
| `sim/actions.py` (`confront`, `_confess`, `conceals`, `infer_suspicions`) | `sim_actions.gd`, `sim_crime.gd` (`confess`), `sim_gossip.gd` | **Pilot 2's machinery, now with something to work on.** A loss makes those who know of it infer suspicions from what they themselves saw and heard; people with a stake confront the suspect. Accused of what they really did, a culprit may confess (more likely the more honest and soft-hearted they are) and hand back what is left. An innocent accused resents it. A guilty person never brings up anything about themselves and never goes looking for the culprit of their own theft. |
| `sim/incidents.py`, `sim/engine.py` (`register_incident`, `incident_for`, `discover`) | `sim_incidents.gd` | **The incident registry.** Family, core event, time, place, who was responsible, victims, intent, motive, linked events (the forced entry, the discovery), discovery (by whom, when, the window, the event), whether it was owned up to, and when a case could start. It is developer-only truth. |

**Truth stays separate from belief.** The event log and the incident registry are the truth.
- The thief knows what they did (`theft_self`, `stash`), and never tells anyone.
- Nobody else knows a theft happened until a count shows a shortfall, a trace is noticed, or the culprit
  confesses.
- What they then believe about who did it is inferred from what they hold, and is often wrong: in Python and
  Godot alike, about a quarter of suspicions fall on the real culprit.
- A theft too small to notice, or from a tin nobody opens, stays undiscovered and unknown to everyone but the
  thief.

## What waits for later pilots

These are the boundaries. Each later layer plugs into the event log, presence intervals, debts, records, money
transfers, beliefs, traces and incidents that pilots 1 to 3A already keep.

- **Violence and accidents (Pilot 3B):** assault, injuries and the clinic, falls, collisions on Mill Road, vehicle
  damage and repairs, people found or missed, deaths.
  - An argument that would turn violent still ends with the argument logged and counted as
    `escalations_deferred`.
  - See [Next: pilot 3B](#next-pilot-3b-violence-and-accidents).
- **Testimony export, suitability and case packaging** (`mystery/cases`).
- **The investigation rules** already run in Godot (`scripts/core/`) and are untouched.

## Determinism

Every random draw comes from a named stream seeded from the run seed, the same way as in Python. There is no
global random generator, no iteration over unordered collections and no transcendental function. Running the
same seed and settings twice gives an identical event-log digest; the tests check this, and CI compares the
digests produced on Windows and Linux.

Nine histories are pinned in `godot/tests/sim_golden.json`. Both the Windows tests and the Linux demo must
reproduce them:

- **Memory off:** Pilot 1's three histories (seed 7 normal, seed 21 tension, seed 5 crisis with 12
  residents). Their digests were pinned before memory existed and are byte-for-byte unchanged by Pilot 2. This
  is the separate validation of the digest change: with the new layer switched off, nothing else moved.
- **Memory on:** the same three runs with perception, memory and gossip. Their histories differ because gossip
  happens in chats, beliefs steer decisions, and the extra random draws shift later ones. They were pinned
  from the Windows run of commit 8d67289 and reproduced on Linux in CI run 29.
- **Crime on:** a month in the tension season (seed 21), the scarcity season (seed 7) and the crisis season
  (seed 5, 12 residents), long enough for thefts to happen in them: 4, 1 and 1 thefts, plus ledger mistakes,
  discovered losses and traces. They were pinned from the Windows run of commit d885ed1, after Linux had
  produced the same three digests, and both platforms reproduce them in CI run 33.

The crime switch is off by default, and the six earlier histories are byte-for-byte unchanged by Pilot 3A
(CI runs 32 and 33). That is the separate validation of this pilot's digest change.

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
- how the piece of news passed on in the most chats got round, person by person, with who told whom and when;
- one misidentification and one drifted rumour, each set against the truth;
- how much one resident has forgotten of Day 1;
- the integrity checks and the event-log digest.

With `--crime`, it also prints the truth about every incident, which no resident sees whole:
- what happened, when, and whether and when it was discovered, and by whom;
- how many people came to know of each loss;
- who suspected whom of it, marked right or wrong;
- accusations, confessions, abandoned attempts and spending from hidden stashes;
- every trace: where it was left, who noticed it, and when it was cleared away.

```bash
godot --headless --path godot -s res://tests/run_sim.gd -- --seed=21 --days=30 --profile=tension --crime
```

**Options:**
- `--out=<folder>` writes the whole history as JSON, with beliefs, incidents and traces.
- `--golden` checks the nine pinned digests.
- `--memory=off` runs pilot 1.
- `--crime` turns on pilot 3A.

CI runs both commands on Linux and uploads the results as the `simulation-demo` artifact.

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

### Crime (pilot 3A)

**Integrity and provenance**, checked on every run with crime on (`sim_check.gd`, `_check_crime`): 20 runs of 30
days (4 seasons, 5 seeds), the three pinned crime months and the whole-month scenario test.

| Rule | What is checked |
| --- | --- |
| Theft | Nobody else was at the place when it happened. The loot went, in exactly that amount, from the container into the thief's own stash. It is in the registry as that thief's theft, at that time and place, and the thief holds it among their wrongdoing. |
| Stashes | Only theft fills a stash. Only its owner empties it: spending, hiding stolen food in their pantry, or handing money back in a confession. |
| Containers | Every till, tin, pantry and stash holds what its owners expect, short only by what was stolen from it or written in twice since it was last counted. |
| Discovered losses | Exactly what was stolen and written in twice since the last count. Explained by those events, which touched that container inside the window. |
| Ledger mistakes | Each one doubles a sale that really happened, for its exact amount, and belongs to an accounting incident with nobody responsible. |
| Incidents | The core event is what happened there and then. Every linked event exists. A discovery was made by the person who counted, after the incident, by the event that found it, and something it explains lies inside its window. |
| Hidden loot and confessions | Only the thief hides their loot, and only at home. Only the culprit confesses, and only to their own wrongdoing; the incident is then out in the open. |
| Traces | Each is made by an event at that place and minute, and removed only by a later clearing-away event there. Whoever noticed one was there to see it while it was there (`perceived` = "trace"). Nobody "notices" a trace of their own wrongdoing. |
| Nobody knows of a theft because it happened | Only the thief holds anything that comes from the theft, the hiding or the spending. Everyone else's knowledge of a loss goes back to a discovery they saw, made, or were told about. A suspicion is inferred from a loss or damage the holder already knew of. A thief never goes looking for the culprit of their own theft. |
| Switch off | With crime off there are no incidents, traces or crime events at all, and no event carries the `discreet` mark. |

**Scenarios** (`tests/test_crime.gd`), on a real town with memories cleared and people placed:

| Test | What it shows |
| --- | --- |
| The switch | Off unless asked for; crime without memory is refused. |
| A theft nobody sees | Half to nine tenths of the till goes into the thief's stash, discreetly. The thief alone knows, even after hiding the loot at home (a trace there). Counting the till the next morning finds exactly that much missing. The incident is discovered by the counter, inside its window, with a case start an hour or two later. The grocer knows the money is gone, the customer there sees it found, the rest of the town knows nothing, and nobody knows who. |
| A forced door | The door is forced and stays open: a trace. Neighbours on the square hear only a noise, not who or what. Whoever opens up sees the door first, then finds the till short ("The back door had been forced."). A day and a half later the first person there by daylight mends it, lawfully, having seen it. |
| Who steals | In money trouble at night, a business till. Without money trouble, early in the evening, if honest, or soon after an attempt: never. Hungry with nothing to eat or pay with: the grocery's stock. |
| Nobody steals in company | With the publican there: no theft, nothing taken, nothing to find. |
| Food and spending | Stolen stock ends up in the thief's pantry. Later, short of money, the thief spends from the stash, quietly, leaving the household tin alone. The robbed till stays short until someone counts it. |
| Undiscovered thefts | A few crowns from a nearly empty till are put down to miscounting and written off. A household tin nobody opens stays robbed. Both stay undiscovered, and only the thief knows. |
| A ledger mistake and a false suspicion | The books expect money that never came in. At closing the till looks short. The grocer, who saw someone by the till and has heard they are struggling, suspects them of a theft that never happened, accuses them, gets no confession, and is resented. |
| Confession | Across eight towns, an honest, soft-hearted culprit accused of what they really did often owns up and hands back what is left. A denial changes nothing. The guilty do not resent a true accusation as the innocent do. |
| Concealment | Before stealing, a resident mentions their own debt in conversation. Afterwards they keep quiet about themselves and the loot. Given the same knowledge of a loss, they do not hunt the culprit of their own theft; someone with nothing to hide does. |
| Whole months | Three crime-on months: no rule broken; thefts happen; losses make people suspect one another. |

### Compared with Python

`tools/sim_reference.py` runs the Python simulation twice, 40 runs each (4 seasons x 10 seeds), with violence and
accidents off: once with stealing off too (`sim_reference.json`, compared with Godot's crime switch off) and once
with stealing on (`sim_reference_theft.json`, compared with Godot's crime switch on). It measures that simulation
exactly as `sim_check.gd` measures the Godot one:

- 20 kinds of event per resident per day;
- where people spend their hours, sleep, needs, money and open debts;
- since pilot 2, memory:
  - beliefs by source, by kind and by error, per resident per day;
  - gossip chats and items passed on;
  - suspicions;
  - for each argument, refusal, missed rent and discovered loss, how many people *not involved* came to know of it;
  - the share of loan requests granted;
- since pilot 3A, with stealing on:
  - thefts, abandoned attempts, forced entries, ledger mistakes, discovered losses, spending from stashes,
    confessions, traces cleared away and accusations, per resident per day;
  - the share of thefts discovered, cash taken per theft, and the share of suspicions that fall on whoever
    was really responsible.

**What the test enforces:**
- Routine and core memory statistics must match within tolerance: beliefs seen and told, gossip chats and items passed on.
- The rest are reported.
- In CI run 29, all 260 statistics (65 per season) were within tolerance.
- With crime on, the same core statistics must match (they do), and across all seasons together Godot's thieves
  must steal as often as Python's within a factor of two: 0.0052 thefts per resident per day (31 thefts) against
  0.0060 (CI run 33). Of the 332 statistics (83 per season), one is outside its tolerance: the share of thefts
  discovered in the tension season (see Known differences).

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

## Results with crime on (CI run 33)

Godot: 5 seeds per season, 30 days, crime on. Python: 10 seeds, stealing on, violence and accidents off. Rates
are per month in a town of 10 (per resident per day x 300). Each cell is Godot / Python.

| Season | Thefts | Thefts discovered | Ledger mistakes | Losses found | Accusations | Suspicions on the real culprit | Others who learn of a loss |
| --- | --- | --- | --- | --- | --- | --- | --- |
| normal | 0.8 / 1.1 | 67% / 86% | 0.6 / 0.9 | 1.2 / 1.9 | 0.8 / 2.1 | 20% / 29% | 7.2 / 7.2 |
| scarcity | 1.6 / 2.0 | 90% / 88% | 1.2 / 0.3 | 2.6 / 2.1 | 5.0 / 3.5 | 9% / 27% | 8.5 / 8.0 |
| crisis | 2.0 / 1.7 | 88% / 94% | 0.8 / 0.5 | 2.4 / 2.1 | 3.2 / 3.0 | 22% / 26% | 9.0 / 8.8 |
| tension | 1.8 / 2.4 | 60% / 100% | 0.4 / 0.2 | 1.6 / 2.5 | 2.4 / 5.0 | 20% / 19% | 8.6 / 8.9 |

- **What is robbed:** household savings tins 22 times and tills 9 times in Godot's 20 months; tins 57, tills 14
  and the stock once in Python's 40.
- **How much:** a theft takes 110-347 crowns on average in Godot and 136-384 in Python, depending on the season.
- **What comes of it:**
  - inferred suspicions: 0.07-0.32 a day in Godot against 0.11-0.36 in Python (the town as a whole);
  - spending from a stash: 3-7 times a month against 2.5-11;
  - confessions are rare on both sides (none in Godot's 20 months, one in Python's 40) and are covered by a
    scenario test instead.
- **Routine is unchanged in character:** every core statistic (sleep, home, work, meals, wages, purchases,
  beliefs seen and told, gossip) matches Python with crime on as with it off.
- **Speed:** 30 simulated days with crime on take 0.57-1.47 s on the Windows CI runner.

## Known differences from Python

### With crime on (pilot 3A)

| Difference | Godot | Python | Why |
| --- | --- | --- | --- |
| Thefts that stay undiscovered | 6 of 31 | 4 of 72 | The same two reasons on both sides (CI run 34 printed each one). Four were in the last days of the month, before the tin or till was opened again. Two took a crown or two from a nearly empty household tin: when it was next opened the shortfall was under 5 crowns, put down to miscounting and written off (Python does the same with a 3-crown theft from the pub till). Python's four are three late and one tiny. Godot's thieves rob poorer tins more often: less taken per theft in most seasons (tension: 110 crowns against 384) and more attempts given up at an empty tin (next row). With 9 thefts in Godot's tension runs against Python's 24, that gives 60% discovered against 100%, the one statistic outside tolerance. |
| Attempts given up (almost all at an empty tin) | 2.6 and 4.2 a month in crisis and tension | 1.7 and 1.9 | Both sides go for a house whose people are all at work, whatever is in its tin, and give up at an empty one; Godot's thieves meet empty tins more often. Every attempt, given up or not, keeps the thief from trying again for four days, so this may also be why Godot's tension season has fewer thefts (1.8 a month against 2.4). Within tolerance. |
| Accusations | fewer in normal and tension, more in scarcity | | Follows from the number of losses found in each season (rare events: within tolerance). |
| A thief may notice the door they forced | yes | yes | Preserved as in Python: what counts as a trace of one's own wrongdoing covers the theft itself and hiding the loot, not a forced entry (whose causes are the thief's money troubles). Harmless: they know anyway. |
| Bookkeeping of a stash and of stolen food in a pantry | the thief's stash and their pantry know what is in them | the stash's and pantry's expected contents are not updated | Nobody ever counts a stash or a pantry, so nothing that happens differs. Godot updates them so that "every container holds what its owners expect, short only by what was stolen from it" can be checked for every container. |
| The `discreet` mark on events | only on discreet events | on every event (true or false) | So that the six histories pinned before Pilot 3A keep their digests. |

### Without crime (pilots 1 and 2)

All are within the test tolerance. With crime on, the first and the ledger-mistake rows below no longer apply:
Godot then forms suspicions (0.07-0.32 a day) and makes ledger mistakes as Python does.

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
- **Dormant suspicion pipeline, without crime.** Suspicion inference, a resident's stake in an incident, accusations, and the "nearby sightings become worth mentioning after an incident" rule have nothing to work on until something is lost or damaged. With crime on (pilot 3A) they are active.
- **Kinds of belief not yet produced.** With crime on, loss, damage, confession, stash and theft_self are produced. Injury, struck, fall, death, missing, collision_self, vehicle_damage, repair and treated wait for pilot 3B.
- **The town's history is told once, at the start.** Old grudges and debts are known to their parties, and told to some others on Day 1 at minute 0, as in Python. The told beliefs point at the history record, not at a chat.
- **Developer-only provenance.** Beliefs are not yet visible in the game, which still plays Python-made cases. Exporting testimony from beliefs belongs to the case-packaging pilot.

## Next: pilot 3B, violence and accidents

**Recommended scope.** Port the rest of the Python crime layer: about 470 lines of Python, roughly the size of
pilot 3A, behind the same `"crime"` switch (or a second switch, `"violence"`, if pilot 3A's pinned histories
should stay as they are).
- **Assault**, replacing `escalations_deferred`: `assault`, `injure`, `kill`. An argument that turns violent;
  injuries of two severities; rarely a death. The aggressor is responsible; blood at the scene is a trace.
- **Falls and collisions:**
  - `check_fall`: someone drunk on Mill Road after dark falls into the ditch.
  - `check_collision`: a driver on Mill Road, far more likely after dark and after drink, hits a walker or the
    fence.
  - Both leave debris and vehicle damage as traces.
- **Afterwards:**
  - `clinic` and the injured resident's account of what happened (`patient_account`), which can be wrong or a
    lie;
  - `repair`: a guilty driver may get the car mended quietly, with scrap in the workshop as a trace;
  - `notice_injury`: people see someone hurt.
- **People found or missed:**
  - `found`: someone lying hurt is found, and the finder raises the alarm;
  - `_missed_people`: someone who died unseen is missed after half a day, and the person fondest of them goes to
    check on them;
  - the body is buried after three days.
- **Hooks:** injury and being "down" in needs and decisions (the clinic and repair options, sleeping it off,
  `truncate` for someone who cannot walk on), and the incident families assault, collision and fall.

**Verification, in the same style as pilot 3A:**
- **Python reference.** Regenerate it with the whole crime layer on. Compare assaults, injuries, falls,
  collisions, deaths, clinic visits and repairs per season, and how many people come to know of each.
- **Integrity.** Every injury has a cause, every repair has damage before it, a death ends that resident's
  whereabouts, and nobody moves or acts while down.
- **Provenance.** An injury is known by those who saw it, treated it, found the person or were told. A
  patient's account is their own claim, which may be untrue. A driver's knowledge of their collision is `self`
  and concealed until it is reported.
- **Scenario tests:**
  - a fight seen and heard;
  - a fall nobody sees, found the next morning;
  - a hit-and-run with a quiet repair;
  - a confession after a fight;
  - someone missed by a carer.

**Untouched:** testimony export, suitability, case packaging, difficulty and the UI. After pilot 3B, the whole
Python simulation would be native, and the next pilot would turn its incidents into Godot-made cases.
