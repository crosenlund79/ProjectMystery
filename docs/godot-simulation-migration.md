# Moving the town simulation to Godot

The goal is a self-contained Godot 4 game in which the town simulation, case generation and the investigation
all run natively, with Python retired from the active architecture. This document covers six pilots:

- **Pilot 1:** residents living in a town.
- **Pilot 2:** what they see, hear, remember and tell each other.
- **Pilot 3A:** theft and financial incidents: who steals, how it is hidden, how it is found, what traces it
  leaves, and whom the town suspects.
- **Pilot 3B:** violence and accidents: fights, falls and collisions on Mill Road, and what follows them:
  injuries and the clinic, damaged vehicles and the workshop, people found hurt, missed or dead.
- **Pilot 4A:** case extraction: the material for an investigation (testimony, traces, records, who lets the
  investigator look where) taken from Godot's own simulated history, with the truth sealed apart.
- **Pilot 4B:** case generation: the suitability report and hints, `.mcase` packaging, and a solvability gate.
  A case becomes playable only if a truth-blind investigator, playing the player's view through the game's own
  investigation engine, reaches the answer.

With pilot 3B, the whole Python simulation runs natively in Godot. One rule then differs from Python on
purpose: shop workers may serve themselves, which ends a deadlock in which the whole town stops buying food (see
[The grocery deadlock fix](#the-grocery-deadlock-fix-a-deliberate-difference-from-python)).

The existing game is unchanged: its bundled cases are still made by Python and played in Godot. Since pilot 4B,
Godot also makes playable cases from its own simulation, without Python. They are written as ordinary `.mcase`
files into the player's case folder, where the game lists them beside the bundled and imported ones.

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

## What pilot 3B adds: violence and accidents

`"crime": true` now turns on the whole crime layer. `"violence": false` turns off just this pilot and runs
pilot 3A exactly: its three pinned histories are reproduced unchanged with that setting. With crime off,
`violence` does nothing, and the six Pilot 1 and 2 histories are unchanged as well.

| Python (`mystery/`) | Godot (`godot/scripts/sim/`) | What it does |
| --- | --- | --- |
| `sim/actions.py` (`confront`, `assault`) | `sim_actions.gd` (`confront`), `sim_violence.gd` (`assault`) | **Fights.** An argument that would turn violent (impulsiveness, drink and resentment) now does, instead of being counted as `escalations_deferred`. The injury is minor, serious (25%), or rarely fatal (1.5% plus up to 2% for drink). Each bystander steps in half the time, and then nobody is badly hurt. Everyone there sees it; next door hears a scuffle. A serious fight leaves blood; a fatal one leaves a body. It is registered as an assault, with the aggressor responsible and a motive (a grudge, drink, or money), and is known at once to the victim (or, if they die, to a witness). The victim resents and distrusts the aggressor, and both keep away from each other for two weeks. |
| `sim/actions.py` (`check_collision`) | `sim_violence.gd` (`check_collision`) | **Collisions.** A driver crossing Mill Road hits something with a chance of 0.04% by day and 0.3% after dark, plus up to 4% (12% after dark) for drink. Six times in ten a walker on the road at that moment is hit (a minor, serious or, 8% of the time, fatal injury); otherwise the white fence. Damage to the vehicle and debris on the road are traces, and anyone near sees or hears it. The driver either stops and owns up, or drives on. Stopping is more likely if they are honest, kind and sober. Owned up to, it is reported openly: an accident, never a case candidate. Driven on from, the driver is guilty and wants the damage mended quietly. A walker hit and left lies on the road if seriously hurt. |
| `sim/actions.py` (`check_fall`) | `sim_violence.gd` (`check_fall`) | **Falls.** Someone very drunk (intoxication 50 or more) walking Mill Road after dark may fall into the ditch: hurt (30% of the time seriously, and then lying there), with scuff marks on the bank. An accident, nobody's doing. What they remember depends on how drunk they were: that they slipped, nothing at all, or (very drunk) that someone they resent and saw that evening pushed them, which is a mistaken inference. |
| `sim/engine.py` (needs, `truncate`), `sim/decisions.py` | `simulation.gd`, `sim_decisions.gd` | **Being hurt.** An injury heals in two days (minor) or six (serious). The injured sleep and rest more, and the seriously hurt do not go to work. Someone lying "down" goes nowhere and grows more stressed. The dead neither move nor act. |
| `sim/actions.py` (`notice_injury`, `patient_account`) | `sim_violence.gd` (`injuries_noticed`, `notice_injury`, `patient_account`) | **What the hurt say.** At the end of each hour, people in the same place notice who is hurt and hear their account. The account comes from the victim's own belief: the truth, a mistake (the drunk who blames someone), or a lie (someone fond of whoever hit them "walked into a door"). |
| `sim/engine.py` (found and missed people), `sim/actions.py` (`found`) | `sim_violence.gd` (`found_checks`, `found`, `missed_people`), `sim_crime.gd` (`tidy_evidence`) | **Found, missed, buried.** Someone lying hurt or dead is found by the first person awake to come by, never by whoever did it. The finder raises the alarm and takes them to the clinic or home. Someone hurt whom nobody has found by mid-morning manages home alone. Someone who died unseen is missed after half a day (between 8:00 and 18:00) by whoever is fondest of them, who goes to check on them. A body that has been found is buried three days later. |
| `sim/actions.py` (`clinic`, `repair`) | `sim_violence.gd` (`clinic`, `repair`), `sim_decisions.gd` | **The clinic and the workshop.** The injured go to the clinic when it is open. The nurse treats them, sees the injury, and writes what they say in the clinic log. A driver with a damaged vehicle has it mended at the workshop, sooner if guilty. The mechanic writes down the driver's explanation; a driver who drove on lies ("Hit a deer out on the ridge road"). The damage is gone, and the old parts lie in the scrap pile, a new trace. |
| `sim/actions.py` (`notice`), `sim/engine.py` (`_notice_evidence`) | `sim_crime.gd` (`notice`, `notice_evidence`) | **Traces of harm.** Blood, debris on the road and a damaged vehicle are noticed the way a forced door is. Noticing one is a belief about damage, which the suspicion machinery of pilots 2 and 3A works on. Debris from a collision nobody owned up to brings the incident to light. |
| `sim/incidents.py` | `sim_incidents.gd` | **Three more incident families:** assault, collision and fall. Each records who was responsible (nobody, for a fall), the victims, whether a driver drove on, and whether it was owned up to on the spot. |

**Truth stays separate from belief.**
- A driver who drove on knows what they hit (`collision_self`) and keeps it to themselves. A driver who owned up
  talks about it.
- Whoever was struck knows only "a vehicle" (or what kind), unless the driver stopped.
- An injury is known only by those who took part, saw or heard it, found the person, treated them, or were told.
- A patient's account may be mistaken or a lie. Both are marked for developers only (`mistaken_inference`,
  `lie`); whoever hears the account does not know.
- A carer who misses someone knows when they themselves last saw them, not when the person died.

**Accidents are not cases.** Falls and collisions happen, and are registered like any incident. A collision
owned up to on the spot is reported openly and is never a case candidate. A fall becomes a candidate in the
registry once someone finds out about it, exactly as in Python. Nothing in the simulation makes a case: that is
for the case-generation pilot to decide (see [Next](#next-pilot-4-evidence-case-validation-and-saved-case-generation)).

## The grocery deadlock fix: a deliberate difference from Python

**The problem, in Python's rules** (`mystery/sim/decisions.py`, the shop option; `mystery/sim/actions.py`,
`shop`):
- Buying food needs someone *else* serving at the grocery: someone who works there and is working.
- On a morning the shop opens, the grocer's and the assistant's households may both have an empty pantry.
  Shopping then outscores working for both: 108 for a household of two (84 alone) against at most 95.
- Both go shopping in their own shop. Neither can buy, neither counts as serving, and nobody else can buy
  either. They try again every hour, for the rest of the month, and the town goes hungry (mean hunger 40-58
  against about 26).
- In a survey of 40 towns a season, with the crime layer off and on, it happened in 29 of 320 Godot months (CI
  run 42) and 21 of 320 Python months. On both sides it came in towns where both shop workers live in
  households of two or more; the one exception was a Godot assistant who lived alone and cared little for work
  (diligence 0.10).
- A related oddity: a diligent grocer living alone seldom leaves work to go shopping, and cannot buy from
  themselves when the assistant is out. In Python such a grocer's pantry is empty after the first open hour on
  49% of shop days (38 towns).

**The fix** (`scripts/sim/sim_actions.gd`, `shop` and `_provision`):
- **Self-service.** Someone who works at the grocery may serve themselves while it is open and nobody else is
  serving.
  - They pay the usual price, from their own purse into the till; the food goes from the shop's stock into their
    household's pantry.
  - The sale is written in the ledger like any other, marked "(self-service)", and its event carries
    `self_service`.
  - It is never on credit: short of money, they buy what they can pay for.
- **Buying during the shift.** A grocery worker on shift whose household is running short buys food during the
  shift. "Running short" is the same need that sends anyone shopping: less than half a week's food, and nobody
  in the household has shopped today. They buy from a colleague who is serving, otherwise by serving themselves.
- **Everything else is as before.** Customers still need someone serving. Every other sale, its price, its event
  and its ledger line are unchanged, and so are ownership and the till's books.
- **Python's rule is kept behind a switch.** `"shop_self_service": false` (`--shop-self-service=off`) runs
  Python's shop rule. It is there only to compare with Python and for the tests: to replay the deadlock, and to
  reproduce every history pinned before the fix. Python itself is unchanged, deadlock included.

**What it changes** (CI run 46):

| | Before the fix | With it |
| --- | --- | --- |
| Months in which the grocery stalls, 40 towns a season, crime off and on | 29 of 320 | 0 of 320 |
| The 29 months that stalled, run again | stalled | all trade to the end, every rule holding |
| Solitary grocers: pantry empty after the first open hour | 49% of shop days (Python, 38 towns) | 108 of 1,560 shop days (6.9%) with crime off, 81 of 1,560 (5.2%) with it on |
| The normal-season crime months that starved (seeds 2, 3 and 5) | hunger 40-58, 25-50 purchases | hunger 25-26, 69-78 purchases |

- **How often workers serve themselves:** about 9 to 11 times a month in a town of 10 (350 to 437 times per 40
  towns).
- **How often the old trap still opens:** both workers serve themselves in the same hour 15 to 32 times per 40
  towns, depending on the season. Each would have started a stall under Python's rule.
- **Routine still matches Python.** Every routine statistic is within tolerance, compared with Python's months
  in which the grocery kept trading. With the crime layer off, per resident per day (Godot / Python):

| Season | Meals | Purchases | Pub meals | Hunger | Hours at work |
| --- | --- | --- | --- | --- | --- |
| normal | 1.97 / 1.92 | 0.237 / 0.220 | 0.024 / 0.055 | 25.3 / 26.3 | 0.300 / 0.300 |
| scarcity | 1.90 / 1.90 | 0.271 / 0.242 | 0.043 / 0.047 | 28.0 / 27.5 | 0.301 / 0.298 |
| crisis | 1.86 / 1.86 | 0.244 / 0.243 | 0.052 / 0.047 | 28.6 / 28.9 | 0.272 / 0.273 |
| tension | 1.94 / 1.87 | 0.243 / 0.223 | 0.018 / 0.032 | 27.1 / 29.0 | 0.300 / 0.300 |

  Shop workers now buy a little more often and eat at the pub a little less (the solitary grocer no longer lives
  on pub meals). Python's lower crisis-season meals, long listed as a difference (1.51 against Godot's 1.89),
  were its stalled months: on the months in which the grocery kept trading, the two agree (1.86 / 1.86).

## What pilot 4A adds: case extraction

`godot/scripts/cases/` derives everything an investigation needs from Godot's own simulated history. Each case
candidate is frozen at its case start, the hour the investigator arrives. It is the extraction half of Python's
`mystery/cases`; the suitability verdict, hints and the playable package came with pilot 4B.

| Python (`mystery/`) | Godot (`godot/scripts/cases/`) | What it does |
| --- | --- | --- |
| `cases/export.py` (`snapshot_hook`) | `case_extract.gd` (`collect`) | **Candidates.** Runs a town and, at the end of the hour each incident's case starts, freezes every candidate from the registry: discovered, and not owned up to. The simulation is not disturbed: its history is the same with extraction as without (checked against a pinned digest). |
| `cases/export.py` (`_Builder`: testimony) | `case_builder.gd` (`_resident`, `_disclosure`, `_status`, `_supports`) | **Testimony from beliefs.** Every living resident's beliefs, after forgetting (`recall`) and as recalled now (a sighting may come back 30-60 minutes off). Kept to themselves: their own wrongdoing (self-protection). Guarded (if honest) or withheld (if not): things that would hurt someone they love. Hedged: things they are unsure of. Each statement is audited: the belief behind it, accurate or mistaken and why, open, guarded or withheld and why, and what it supports. |
| `cases/export.py` (`_whereabouts`, the deer, the fight) | `case_builder.gd` | **Lies, only where the history gives a reason.** Someone responsible whom nobody saw at it gives a false account of where they were (audited with the true account it hides). A driver who drove on explains the damage with a deer. Someone who started a fight says the other did. |
| `cases/testimony.py` | `case_text.gd` | **Wording.** "I saw", "I heard", "X told me", "I reckon", the speaker's own experiences in the first person, the plain and the exact account of where someone was, and summaries of everyday matters ("I saw Ana, Ben and Cat at the pub ..."), each standing for its member statements. |
| `cases/export.py` (`_consent`, `_evidence`, `_records`, `_vehicles`) | `case_builder.gd` | **Traces, records, vehicles, and where they can be found.** Every trace still there at the case start (one cleared away, mended or buried before then is gone). The last four days of every book: the ledger, the pub's tabs, the clinic log, the workshop orders. Every vehicle and where it is parked. Public places are open. A private place, its books and the vehicles parked there need the owner's leave. An owner hiding a trace of their own doing refuses, and so does a very private household. |
| `cases/relevance.py` | `case_relevance.gd` | **Relevance.** Every statement, trace and record line is connected, unrelated or uncertain, from the incident's causal web. Truth-blind: a lie is judged by what it covers. Identity-blind: whereabouts are judged by place and time, so checking one never singles out the culprit. |
| `cases/export.py` (`_investigation`, `_truth`) | `case_builder.gd` | **Two views of one instant.** The investigation holds the hook, people, places, what each resident is willing to say (text only), and the traces and records the investigator can reach. The sealed truth holds the incident, its causal chain, the answer and narrative, private states, and audits of every statement, trace (with where it is and whether, and by whom, it is kept out of reach) and record line. |
| `diagnostics/integrity.py` (`check_spoiler_boundary`, `check_case`) | `case_extract.gd` (`spoiler_problems`, `provenance_problems`) | **Checks** (extended): see [How it is verified](#case-extraction-pilot-4a). |

**Case principles.**
- **A candidate is not a case.** `eligibility` marks which candidates a playable mystery could ever be made of:
  only an incident with someone genuinely responsible for a crime (a theft, a fight, a collision driven on
  from).
  - Never eligible: a fall, which is nobody's doing; a ledger mistake, which is no crime; a collision owned up
    to on the spot, which is no candidate at all.
  - A suspicion is not an incident and never makes a case.
  - Whether an eligible candidate is actually solvable is decided by pilot 4B's gate.
- **Nothing invented afterwards.** Every statement comes from a belief its speaker held by the case start, or
  is an audited lie the history gives them a reason to tell. Every trace is still there, every record line was
  written, and every account of someone's movements matches the presence record (or is the culprit's audited
  lie).
- **Contradictions are real.** Testimony disagrees only through actual beliefs: misidentifications, drifted
  times, wrong suspicions, loyalty, and lies by whoever has something to hide.
- **The investigator never gets privileged knowledge.** The view has no event or belief ids, no audit field, no
  verdict and no causal link. A trace behind a refusal is not in it at all.
- Python's statement keys (`K0001`), trace and record references (`T-…`, `R-…`), topics and vocabulary are kept,
  so pilot 4B packages the material in the existing case format. Case identifiers follow Python's
  (`<seed>-<season>-<days>d-r<residents>-<incident>`) behind a `godot-` prefix (since pilot 4B). Without it, a
  Godot-made case could share an id, and a save slot, with a different, Python-made case from the same seed.
  How residents recall things at the case start is still keyed by the unprefixed id, as in Python.

## What pilot 4B adds: case generation

`godot/scripts/cases/` now goes all the way from a simulated town to playable `.mcase` files, with no Python. It
is the rest of Python's `mystery/cases`, plus a solvability gate that Python never had.

| Python (`mystery/`) | Godot (`godot/scripts/cases/`) | What it does |
| --- | --- | --- |
| `cases/suitability.py` (`evaluate`, `exposed_lies`, `only_one_there`) | `case_suitability.gd` (`evaluate`) | **The suitability report.** The independent channels (witnesses by root, exposed lies, physical traces, record lines), the deduction routes and the verdict (obvious, playable, ambiguous, unsolvable). It is worked out from the truth (who is accurate, who lies), so it is sealed with the truth and decides nothing on its own. It feeds the difficulty label, the score of a "cannot be determined" verdict, and the reveal (channels the player missed). |
| `cases/suitability.py` (`hints`) | `case_suitability.gd` (`hints`) | **The hint ladder** (nudge, lead, strong hint), pointing only at things the player can actually find. |
| `cases/package.py` | `case_package.gd` | **The package.** The existing format, unchanged (`docs/case-format.md`). The truth is sealed with `sha256-ctr-xor/1`, each relevance verdict with `sha256-xor-item/1`. Everything is ASCII JSON with sorted keys, so a seed gives the same bytes on every platform. `generator.tool` is `mystery (Godot)`, and `generator.options` records the switches the town ran with. |
| (none) | `case_solver.gd` | **The truth-blind investigator** (below). |
| `cases/library.py` (`select_cases`, `build_library`) | `case_generate.gd` | **Generation.** It runs a town and freezes every candidate. Each candidate is packaged and read back exactly as the game reads a file, then judged. Playable cases go to the player's case folder (`user://cases/`, with `run_sim.gd --generate --library`), where the game lists them as imported cases. The bundled library, imported cases and saves are not touched. |

**The solvability gate.** A candidate becomes a playable case only if all of these hold:
1. **It is eligible.** Someone is genuinely responsible for a crime. Accidents, bookkeeping mistakes and
   incidents owned up to on the spot are rejected first. A suspicion is never an incident.
2. **The package validates.** It passes the game's own loader (`CaseFormat`), carries no truth in the player's
   view, and has hints.
3. **The truth-blind investigator solves it.** It plays a copy of the package that holds only the player's
   view: no sealed truth, no relevance verdicts, no summary or generator. It plays through the real
   investigation engine (`scripts/core/investigation.gd`), under the game's rules:
   - It asks every living resident about every topic. It presses where people hesitate or dodge, as far as
     their goodwill goes, and asks for "more" and "earlier".
   - It looks at every place and vehicle it is allowed to, reads every book it is allowed to, and copies the
     lines into the notebook.
   - Then it reasons from the notebook alone (statements, traces, record lines) and from the contradictions the
     player's own timeline shows. It either submits a theory with the entries it rests on, or says why it
     cannot.
   - It never buys hints or uses Hobby Detective checks, which open sealed relevance verdicts.
4. **Only now is the seal opened**, to check the conclusion. The investigator must have named:
   - the person really responsible;
   - the real explanation;
   - a motive the truth accepts.

   Nothing it cited may be mistaken, or a lie other than the culprit's own, and at least one cited entry must be
   evidence of the answer (the game's own scoring, `Verdict`).

A case that fails any step is rejected, with the reason. Nothing is ever added to a case to make it solvable.

**Lines of reasoning.** One logically sufficient chain is enough; channels are never counted.
- **Theft.** Someone's own account of the time in question is proven false. The proof can be:
  - a record (the ledger, the bar tab, ...) that puts them elsewhere;
  - another first-hand statement of their own;
  - two independent eyewitnesses.

  One witness against one account is word against word and proves nothing: witnesses misidentify people and
  misremember times. That person alone must be caught out. If two accounts are disproved, nothing tells the two
  apart, and the case is rejected. The motive is the money trouble people describe (debts, credit, refused
  loans, missed rent). Failing that, it is bad blood with the household robbed. With neither, the case is
  rejected.
- **Assault.** Someone who was there names the attacker: the victim ("X attacked me") or an eyewitness ("I saw
  X attack Y"). Nobody who was there may name anyone else. The fighter's own "they started it" is self-serving
  and does not count. The motive is one of:
  - drink, if someone saw the attacker the worse for drink, or the tab has them at three drinks or more, in the
    five hours before;
  - money, if the quarrel was over money owed;
  - otherwise bad blood, if a quarrel or a grudge between them is known.
- **Collision.** One vehicle shows damage that matches what was hit (white paint and splinters for the fence; a
  smear or a cracked windscreen for a person).
  - The damage is known from a trace on the vehicle, a sighting since the time in question, or a repair since
    then (with its mended parts in the scrap pile, which carry no date of their own).
  - Damage seen before the time in question rules the vehicle out, unless the workshop book shows it mended
    since.
  - One person is tied to that vehicle: their own story of how it was damaged (the deer), or the workshop's
    repair book.
  - The motive is panic, because they drove on.
- Rumours, "If you ask me ..." suspicions, hearsay and a vehicle glimpsed in the dark never decide anything.

**Truth-blindness**, by construction and by test:
- the investigator is given a package with no sealed truth or relevance at all;
- the number of times the seal has been opened (`Verdict.unseal_count`) is unchanged by its work;
- in a full game, the seal is opened only at the reveal.

## In the game: New Case > Generate Mystery

The generator is in the game's menus (`scripts/ui/generate_screen.gd`, on top of
`scripts/cases/case_generation_job.gd`). It is a dedicated menu operation: no investigation is open and no other
town is simulated meanwhile.
- **Settings:** town size (8, 10 or 12 residents, default 10), conditions (normal, scarcity, crisis, tension),
  days to simulate (14-120, default 60), an optional seed (random when empty), and how many towns to try at
  most (1-40, default 12).
- **The work:** one request is done a little at a time, without threads. The screen gives it 12 ms a frame, in
  whole units:
  - an hour of the town;
  - freezing a case candidate;
  - packaging it;
  - questioning one resident;
  - the investigator's conclusion and the sealed check;
  - saving.

  Towns are tried seed after seed (the chosen seed, then the next ones). In each town, every candidate is
  judged as soon as the investigator would arrive, exactly as `case_generate.gd` judges it, and the first that
  passes is kept. The town is simulated no further than needed: the case is frozen at its start, so it is the
  same as a whole run gives.
- **What is shown:** the town number, the seed, the day (as a progress bar), what is being done, and how many
  possible cases have been looked at. Never a culprit, a motive, an incident or anything sealed.
- **Cancel** takes effect between units, at once. Nothing has been written by then.
- **Saving:** only a case that passed the gate is saved, written whole (to a `.part` file, checked, then
  renamed) into the player's case folder.
  - It is never written over a different file of the same name; that case is passed over and the search goes on.
  - The same case already there is recognised and offered as it is, not written again.
  - The case library lists it as "generated", with its seed, beside the bundled and imported cases.
- **After a mystery is found:** Investigate, Generate Another (the same settings; cases already in the library
  are not offered again), or Case Library.
- **If every town fails:** the reason, then Retry (the next towns) or Back.

## What waits for later pilots

With pilot 4B, nothing in Python is needed any more to make or play a case. What remains is product work, not
migration:
- difficulty settings and custom generation settings (the next iteration);
- more cases per month, and better ones (see the [recommendation](#next-after-pilot-4b));
- an installer.

**The investigation rules** run in Godot (`scripts/core/`) and are unchanged in behaviour. Two internal changes
were made:
- the timeline's contradiction finder can now also be called without a game in progress (static), with the
  same results;
- the evidence part of the score also reports how many cited entries were good and bad.

## Determinism

Every random draw comes from a named stream seeded from the run seed, the same way as in Python. There is no
global random generator, no iteration over unordered collections and no transcendental function. Running the
same seed and settings twice gives an identical event-log digest; the tests check this, and CI compares the
digests produced on Windows and Linux.

Twenty-six histories are pinned in `godot/tests/sim_golden.json`. Both the Windows tests and the Linux demo
must reproduce them.

**The grocery deadlock fix changed every history pinned before it.** In each of the twelve, shop workers buy
during their shifts within the first week, and every later draw shifts.
- **Under Python's shop rule:** the twelve digests pinned before the fix are kept, under the same keys marked
  "Python's shop rule". They are reproduced with `"shop_self_service": false`, the separate check that the fix
  changed nothing else.
- **With the fix:** the plain keys hold the new histories. They were pinned once the Windows tests and the Linux
  demo had produced the same twelve new digests (CI run 46).
- **Two more months with the fix:** the fix also changed what happens in the three full-crime months (now a
  single fall between them). So two more are pinned with the fix, chosen because violence happens in them:
  - seed 2 tension holds three collisions, two driven on from, and a quiet repair;
  - seed 4 tension holds a fight, treated at the clinic.

The twelve histories, as described below, are those under Python's shop rule:

- **Memory off:** Pilot 1's three histories (seed 7 normal, seed 21 tension, seed 5 crisis with 12
  residents). Their digests were pinned before memory existed and are byte-for-byte unchanged by Pilot 2. This
  is the separate validation of the digest change: with the new layer switched off, nothing else moved.
- **Memory on:** the same three runs with perception, memory and gossip. Their histories differ because gossip
  happens in chats, beliefs steer decisions, and the extra random draws shift later ones. They were pinned
  from the Windows run of commit 8d67289 and reproduced on Linux in CI run 29.
- **Crime on, violence off:** Pilot 3A's months in the tension season (seed 21), the scarcity season (seed 7)
  and the crisis season (seed 5, 12 residents), long enough for thefts to happen in them: 4, 1 and 1 thefts,
  plus ledger mistakes, discovered losses and traces. They were pinned from the Windows run of commit d885ed1,
  after Linux had produced the same three digests, and both platforms reproduced them in CI run 33. Since
  pilot 3B they are run with `"violence": false`, and their digests are unchanged (CI runs 37 to 44).
- **The whole crime layer:** a month in the tension season (seeds 1 and 3) and the crisis season (seed 1),
  chosen because violence happens in them.
  - Seed 1 tension holds a fight, a fall found the next morning, and a driver who hits the fence on Mill Road,
    drives on, and has the truck quietly mended the next day.
  - Seed 3 tension holds a fall, whose victim is found lying hurt and treated.
  - Seed 1 crisis holds a fight, treated at the clinic.
  - They were pinned from the Windows runs in CI runs 38 to 42, which all agree. Linux reproduces them in runs
    42 to 44.

The crime switch is off by default, and the six earlier histories are byte-for-byte unchanged by Pilot 3A
(CI runs 32 and 33). Pilot 3B draws random numbers only when violence is on, and what it adds to needs and
decisions is zero for anyone unhurt, so the six crime-off and the three violence-off histories are unchanged by
it (CI runs 37 to 44). That is the separate validation of each pilot's digest change.

Python's random numbers are not reproduced. The two simulations follow the same rules with different random
draws, so they are compared by their statistics, not event by event.

**Case files** (pilot 4B) are pinned too. Every package of two months (seed 1 and seed 2, tension; nine
candidates) is in `godot/tests/case_golden.json` by SHA-256, playable or not. Packages are written as ASCII JSON
with sorted keys. Both the Windows tests and the Linux demo (`--generate --golden`) must reproduce them, and
they have since CI run 55. Generating cases leaves those months' pinned histories unchanged.

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
- how many people came to know of each theft, fight, fall or collision;
- who suspected whom of it, marked right or wrong;
- accusations, confessions, abandoned attempts and spending from hidden stashes;
- every trace: where it was left, who noticed it, and when it was cleared away, mended or buried;
- who is hurt or dead at the end.

```bash
godot --headless --path godot -s res://tests/run_sim.gd -- --seed=1 --days=30 --profile=tension --crime
```

**Options:**
- `--out=<folder>` writes the whole history as JSON, with beliefs, incidents and traces.
- `--golden` checks the twenty-six pinned digests.
- `--memory=off` runs pilot 1.
- `--crime` turns on the whole crime layer (pilots 3A and 3B); `--violence=off` with it runs pilot 3A only.
- `--shop-self-service=off` runs Python's shop rule, without the grocery deadlock fix.
- `--cases` (pilot 4A) freezes every case candidate at its case start. For each it prints the hook, whether a
  playable mystery could ever be made of it and why, how much testimony there is and of what kind, the traces on
  view or behind a refusal, the culprit's own account of where they were, the sealed narrative, and the result
  of the provenance and spoiler checks. With `--out`, it writes each case's investigation and sealed truth as
  JSON.

```bash
godot --headless --path godot -s res://tests/run_sim.gd -- --seed=1 --days=30 --profile=tension --crime --cases --out=sim-demo
```

- `--generate` (pilot 4B) makes playable cases from a month with the whole crime layer. For every candidate it
  prints:
  - whether it is playable, or where and why it was rejected;
  - what the truth-blind investigator concluded, after how many questions, places, vehicles and books;
  - the check against the sealed truth afterwards;
  - the quality concerns;
  - the package's size and SHA-256.

  With `--out`, the playable cases go to `<out>/cases/` and every package (playable or not, for inspection) to
  `<out>/all/`. With `--golden`, the package bytes are checked against `tests/case_golden.json`, and the history
  against `tests/sim_golden.json`.

```bash
godot --headless --path godot -s res://tests/run_sim.gd -- --seed=1 --days=30 --profile=tension --generate --golden --out=sim-demo/generated
```

With `--library`, the playable cases go straight into the game's own case folder (`user://cases/`; on Windows
`%APPDATA%\ProjectMystery\cases`). The game then lists them under New Case, beside the bundled and imported
cases. A `.mcase` file can also be imported from Load Case.

```bash
godot --headless --path godot -s res://tests/run_sim.gd -- --seed=2 --days=30 --profile=tension --generate --library
```

CI runs these commands on Linux and uploads the results as the `simulation-demo` artifact.

```gdscript
var sim = preload("res://scripts/sim/simulation.gd").new({"seed": 7, "days": 30, "profile": "tension"}).run()
for ev in sim.events.events:
    print(ev["time"], " ", ev["summary"])
for b in sim.memory[sim.ids[0]].beliefs:
    print(b["source"], " ", b["claim"]["kind"], " ", b["confidence"])
```

## How it is verified

`godot/tests/test_sim.gd`, `test_memory.gd`, `test_crime.gd`, `test_violence.gd`, `test_grocery.gd`,
`test_extraction.gd` and `test_generation.gd` are part of the Godot test run in CI.

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

### Violence and accidents (pilot 3B)

**Integrity and provenance**, checked on every run with the whole crime layer (`sim_check.gd`, `_check_violence`
and the extended `_check_crime`): 20 runs of 30 days (4 seasons, 5 seeds), the three pinned months and the
scenario tests. The pilot 3A rules above still hold.

| Rule | What is checked |
| --- | --- |
| The living and the dead | Whoever is dead died once, of a fight or a collision, and their body lies where they died. The dead neither move nor act afterwards. |
| Injuries | Every injury names the event that caused it, and that event harmed that person. |
| Fights | Each follows an argument between the two. A serious one left blood; a fatal one killed the victim. Each is registered as the aggressor's assault. |
| Collisions | Each follows that driver's drive along Mill Road, in their household's vehicle, within the hour. Each left damage on the vehicle and debris on the road. The driver drove on exactly when they are guilty of it; one who stopped owned up, and the incident is reported openly. |
| Falls | Each follows a walk along Mill Road, and is registered as nobody's doing. |
| The clinic | Only the nurse treats, only at the clinic, and only a harm that befell the patient. |
| Repairs | Each follows damage to that vehicle, happens at the workshop, and leaves scrap. |
| Found, missed, buried | Whoever found someone was there at the time. Only the dead are missed. A burial follows a found body after three days. |
| Vehicles | Replayed drive by drive: each drive starts where the last one ended, the last ends where the vehicle is, and only the household that owns the vehicle drives it. |
| Traces and discovery | Damage on a vehicle is wherever the vehicle is. A trace disappears only when it is cleared away, buried or mended. An incident is discovered by someone who took part in it or perceived it, no earlier than it happened, and its window holds the harm. For the fence, whose damage may be found days later, only the end of the window is checked. |
| Who knows what | Only the driver holds that they hit something; only the person struck, that they were struck. A patient's account is "told" by the patient, copied from their own belief, when they were found, treated or seen hurt. The mechanic's note of the explanation comes from the driver. A `lie` is only ever told; a `mistaken_inference` is only inferred or passed on. |
| Switch | With violence off (and with crime off) there are no fights, interventions, deaths, collisions, falls, finds, treatments, repairs or burials at all, and nobody is hurt or dead. |

**Scenarios** (`tests/test_violence.gd`), on a real town with people placed:

| Test | What it shows |
| --- | --- |
| A fight | An argument turns into a fight: registered as the attacker's, after the argument. The witness in the room sees it; the square only hears a scuffle. Blood if it was serious; a body if it was fatal; otherwise the victim is hurt and untreated. The victim resents and distrusts the attacker. |
| Peacemakers | With three bystanders, someone usually steps in, and then the injury is minor at most. |
| Collisions | Across many towns, a drunk driver on Mill Road at night hits a walker or the fence. The damage and the debris are traces. The driver knows what they hit; whoever was struck knows it; another walker on the road sees it. A driver who drives on is guilty and wants the damage mended quietly. Someone seriously hurt is left lying on the road; someone with a minor injury walks on. A driver who stops owns up: an accident, out in the open, and the one struck knows who hit them. |
| Falls | A drunk walker falls into the ditch: an accident, hurt, scuff marks on the bank, lying there if badly hurt. Exactly one memory of how it happened. Too drunk to know, they may blame someone they resent and saw that night: a mistaken inference. |
| Found and treated | Someone lying hurt is found by the first person to come by and says they slipped into the ditch. The finder is told; the nurse treats them, sees the injury, hears the account and writes it down. |
| Home alone | Nobody comes by: by mid-morning someone hurt manages home on their own. |
| What the hurt say | An honest patient names who hit them; one fond of the attacker says they walked into a door (a lie). Either way the nurse sees the injury. |
| Repairs | The workshop mends a damaged vehicle; the damage is gone and the old parts lie in the scrap pile. A driver who drove on tells the mechanic a lie (a deer on the ridge road); one who owned up tells the truth. |
| A death | Not missed before half a day has passed; then missed by whoever is fondest of them, who knows only when they last saw them. Found where they lie by someone passing; buried three days later, not before. |
| Concealment | After driving on, a driver says nothing of it in conversation; having owned up, they talk about it. |
| Whole months | Three months with the whole crime layer: no rule broken. |

Every scenario and every whole month also checks that every belief has a plausible source.

### The grocery (the deadlock fix)

**Every sale**, in every simulated month (`sim_check.gd`, `_check_shop`):
- it happens while the grocery is open, at the season's price;
- the money goes from the buyer's purse into the till, and the food from the shop's stock into the buyer's
  household pantry, nothing else;
- it is served by someone else who works at the grocery and is in the shop, or it is marked self-service and the
  buyer works there.

**Scenarios** (`tests/test_grocery.gd`):

| Test | What it shows |
| --- | --- |
| Self-service | Monday morning, nobody serving, both workers' pantries empty: both serve themselves, each a week's food for their household. The usual price is paid from their own purses; the money is in the till, the food has left the stock, the till holds what the grocer expects, and both sales are in the ledger marked self-service. No credit. |
| Only for shop workers, only when open | A customer alone in the shop, with nobody serving, still cannot buy, and may come back later. A worker gets no self-service on Sunday, after closing or before opening. |
| A colleague serves | With the assistant at work, the grocer buys from the assistant, as does a customer: ordinary sales. |
| No credit to oneself | A worker short of money buys only what they can pay for. With no money: nothing, no credit, and no second try that day. |
| Buying during the shift | A grocer living alone, working on Monday with an empty pantry and the assistant not yet in, serves themselves without leaving work, once that day. On Tuesday, running short with the assistant serving, they buy from the assistant. With half a week's food at home, nothing. |
| The old deadlock, replayed | A town where both workers live in households of two, run to Monday Day 8, when the grocer's, the assistant's and a customer's pantries are found empty. Under Python's rule both workers go shopping in their own shop, and not one sale follows to the end of the month. With the fix the same trap opens: both serve themselves in that hour, both are back at work by noon, others are served that day (the customer's household too), and the shop trades to the end of the month. |
| Every month that stalled before | All 29 months that stalled in the survey before the fix (13 with crime off, 16 with it on) are run again. None stalls, every rule holds, and in 33 hours among them both workers served themselves, each the start of a stall under Python's rule. |
| Solitary grocers | In 8 normal-season towns whose grocer lives alone, the pantry is empty after the first open hour on 3 of 208 shop days (Python without the fix: 49%). |

Every Python comparison run must also trade to the end of the month (next section).

### Case extraction (pilot 4A)

`tests/test_extraction.gd` freezes every case candidate of 20 months with the whole crime layer (4 seasons x 5
seeds): 51 cases, 27,225 statements, 97 traces and 4,602 record lines (CI run 52).

**Every case** (`case_extract.gd`, `provenance_problems`, run at the case start):

| Rule | What is checked |
| --- | --- |
| The spoiler boundary | The investigation view holds no event id (E000123), no belief id (B000123) and none of the truth's fields: status, lie, error, belief, event, supports, intent, causes, implicates, responsible, answer, narrative, chain, guilty_of, traits, disclosure, segments, eligibility and the rest. |
| Statements | Every statement has an audit entry for its speaker, who is alive at the case start. A truthful statement is its speaker's own belief, held by then, told as it came ("saw" as seen, "told" as told), and reads exactly as that belief renders when recalled at that moment. A mistake has a cause. A summary stands for two or more real statements. A thief's own knowledge of their theft never appears. |
| Lies | Each has an explanation and a reason in the history. A false account of someone's movements comes only from whoever is responsible, and the true account it hides matches the presence record. A made-up story covers that person's own incident. A fighter's lie is about a fight they started. |
| Accounts | Every truthful account of where someone was matches where the presence record puts them. |
| Withheld | Nothing withheld to protect oneself is in the view, and everything withheld is the speaker's own belief. |
| Traces | Each one in the view is where it says, still there at the case start, left by something that had happened by then, and in the evidence audit. No trace is shown where the investigator may not look. One gone before the case start is in neither view. |
| Records | Each line in the view is the book's line as written, by the case start, after the event it records. |
| Relevance | Every "connected" verdict comes from an event in the incident's causal web. |
| The answer | The sealed answer names whoever was responsible; the chain includes the incident and nothing after the case start; an eligible case has someone responsible for a crime. |

**Scenarios and properties** (`test_extraction.gd`):

| Test | What it shows |
| --- | --- |
| Determinism | The same month gives byte-identical cases twice, and extracting them leaves the pinned history (seed 1, tension) unchanged. |
| Candidates | Every incident discovered and not owned up to by its case start has a case, frozen at that instant; none comes from an incident nobody discovered. Eligibility follows the rule above. Of 51 candidates, 34 could be playable (29 thefts, 3 collisions, 2 fights). 17 never could: 15 ledger mistakes and 2 falls. |
| Mistaken identities, drifting times, false suspicions | 125 statements put the wrong person (or the right one at the wrong time) somewhere. 1,939 have a drifted time and 1,459 are wrong suspicions. A wrong suspicion pointing at anyone but the case's culprit is marked misleading, and none is marked correct. |
| Loyalty | 594 statements guarded and 984 withheld to protect someone the speaker loves. |
| Concealment | In all 29 theft cases with the thief alive, the thief withholds their theft and their hidden stash (198 things withheld for self-protection in all) and never tells of them. |
| Lies | 46 false accounts of their movements by whoever was responsible, and 3 deer. |
| Missing and out-of-reach traces | 26 traces were cleared away, mended or buried before a case started and appear nowhere. 77 are kept from the investigator by a refusal (a thief's stash at home, damage on a guilty driver's car), each audited with who refused, none in the view. 20 are on view. |
| Undiscovered incidents | No case, and no visible statement tells of one. |

### Case generation (pilot 4B)

`tests/test_generation.gd` checks the investigator's rules on small hand-made cases, the package, its
determinism, and then forty months with the whole crime layer (4 seasons x 10 seeds, as many as Python's
reference). Each month runs in 1-6 seconds on the CI machine, generation included.

**The truth-blind investigator's rules, on hand-made cases.** Each case is a five-household town, played through
the real engine.

| Case | Expected | What it shows |
| --- | --- | --- |
| The ledger has the thief at the grocery while she says she was at home all day; she is in debt; three people think someone else did it | the thief, stolen, money trouble, citing the account, the ledger line and the debt | A record disproves an account; rumours ("If you ask me, Ben ...") count for nothing. |
| The same, but the grocer will not show the ledger | no conclusion | Evidence out of reach is not used. |
| One witness against her account | no conclusion: word against word | One witness may have mistaken someone or the time. |
| Two independent witnesses | the thief | |
| The second witness tells only when pressed, and has no goodwill left; then has one | no conclusion; then the thief | The investigator presses where people hesitate, within the game's goodwill rules. |
| The same witness twice; hearsay against her account | no conclusion | One person is one witness; "X told me" is no witness. |
| A mistaken witness against an innocent man's account, and rumours about him, while the ledger disproves the thief's | the thief, not him | Misleading testimony. |
| Two accounts disproved by records | no conclusion: two suspects | Nothing tells them apart, so the case is rejected. |
| No motive anyone knows of; then a grudge against the household robbed | no conclusion; then grudge | |
| A fight: the victim names the attacker, the attacker says the other started it, a witness saw a quarrel over money | the attacker, assaulted, money trouble | The fighter's own claim does not count. |
| The same, with four drinks on the attacker's tab | intoxication | |
| Two people who were there name different attackers; only hearsay names him | no conclusion | |
| A truck with white paint and splinters in its grille, its driver's deer story, and a glimpse of another car "I think Dan was driving" | the truck's driver, vehicle collision, panic | The glimpse in the dark decides nothing. |
| The truck behind a refused door; damage seen before the time in question; two damaged vehicles | no conclusion | |
| Damage seen before the time in question, but mended in the workshop book since | the truck's driver | A repair clears earlier damage. |
| Another car's mended parts in the scrap pile, from a repair before the time in question | the truck's driver | Undated scrap counts only with a repair after the time in question. |

The seal is never opened while the investigator works (`Verdict.unseal_count`).

**The package.**
- A truth with non-ASCII text (dashes, curly quotes) seals as ASCII and opens with the game's own `unseal`, and
  not under another case id.
- Relevance verdicts open one at a time with the game's `open_relevance`.
- **Determinism.** Two months (seed 1 and seed 2, tension) are generated twice. Every package is byte-identical,
  and the months leave their pinned histories unchanged. All nine packages are pinned in
  `tests/case_golden.json`. CI run 55 produced them identically on Windows (the tests) and Linux
  (`run_sim.gd --generate --golden`), and every run since checks them on both.
- **Python reads them.** In CI, `tools/check_godot_cases.py` reads every package the Linux job made (playable or
  not) with Python's own `validate_package`, which is stricter about integer types. Python's `unseal` opens each
  sealed truth, which belongs to the same case and holds a suitability report. A reference check only: the game
  needs no Python.

**Forty months.** Every candidate is judged, with these checks:
- **Every playable case:**
  - the investigator's conclusion matches the sealed answer (person, explanation, an accepted motive);
  - nothing it relied on is mistaken;
  - the file is written, loads, and is byte-identical to the judged package;
  - the hints come in rising tiers, cost what they say, fit the credits, and name only residents of the case;
  - the summary does not name the culprit.
- **Every playable case is then played as a game** (`CaseGenerate.playthrough`):
  - the case library finds it as an imported case and opens it;
  - the investigator plays it in an ordinary game opened from the full package;
  - the game is saved half way and resumed, with the same notebook;
  - the theory is submitted and the case revealed;
  - the seal is opened only at the reveal; the score is 80 or more; a revealed case stays closed after saving.
- **Every rejected case:**
  - it has a reason, and nothing is written;
  - every ledger mistake and fall is rejected as ineligible;
  - on those, the investigator, asked anyway, concludes nothing.
- **Never a false accusation.** No case, eligible or not, in which the investigator would name anyone but the
  culprit.
- **The library afterwards:**
  - the generated cases sit beside the 15 bundled ones, with no id listed twice, and none in the `godot-`
    namespace is bundled;
  - a save made for a bundled case before generating and playing new cases is byte-identical afterwards, and
    still resumes;
  - a generated case can also be imported from elsewhere through the game's own importer.

### Compared with Python

`tools/sim_reference.py` runs the Python simulation three times, 40 runs each (4 seasons x 10 seeds):
- with the crime layer off (`sim_reference.json`, compared with Godot's crime switch off);
- with stealing only (`sim_reference_theft.json`, compared with Godot's crime on and violence off);
- with the whole crime layer, as Python normally runs (`sim_reference_crime.json`, compared with Godot's crime
  on).

It measures that simulation exactly as `sim_check.gd` measures the Godot one:

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
    was really responsible;
- since pilot 3B, with the whole crime layer:
  - fights, falls, collisions, deaths, interventions, stopping after a collision, damage found, people found
    hurt or dead, people missed, treatments, repairs and burials, per resident per day;
  - the share of collisions driven on from, the share of harmful incidents discovered, and how many people
    come to know of a fight;
- whether, and from which day, the grocery stalled (`stall_day`), and the statistics over the months in which
  it kept trading.

**What the test enforces:**
- Routine and core memory statistics must match within tolerance: beliefs seen and told, gossip chats and items passed on.
- The rest are reported.
- In CI run 29, all 260 statistics (65 per season) were within tolerance.
- With crime on, the same core statistics must match (they do), and across all seasons together Godot's thieves
  must steal as often as Python's within a factor of two: 0.0052 thefts per resident per day (31 thefts) against
  0.0060 (CI run 33). Of the 332 statistics (83 per season), one is outside its tolerance: the share of thefts
  discovered in the tension season (see Known differences).
- **Since the grocery deadlock fix**, Godot's grocery never stalls, and all three comparisons check that for
  every Godot month. Python's still can: a stalled month is an absorbing state in which hunger, purchases and
  sightings for the rest of the month are about the stall and nothing else. With ten months a season, one stall
  moves the mean hunger by about three points. So Godot is compared with Python's months in which the grocery
  kept trading, and Python's stall count is reported. That leaves out 3 of Python's 10 crisis months with the
  crime layer off and with stealing only, and 2 with the whole layer.
- With the fix, all core statistics match in all three comparisons (CI run 46). Outside tolerance, among the
  non-core statistics, there is one: with stealing only, others who learn of missed rent in the crisis season
  (1.9 against 1.1).
- Violence is too rare to compare season by season (a season's five months hold none to three of each kind), so
  across all seasons together Godot must have harm, and the counts are reported against Python's rates. Each
  mechanism is covered by a scenario test instead.

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

## Results with stealing only: crime on, violence off (CI run 33)

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

## Results with the whole crime layer (CI run 43, before the grocery fix)

**All tests:** 107 tests and 17,858 checks pass on Windows. Linux reproduces all twelve pinned histories.

**Routine and knowledge.** Godot: 5 seeds per season, 30 days. Python: 10 seeds. Compared on the months in
which the grocery kept trading: all of Godot's but 3 normal-season months, and all of Python's but 2 crisis
months. Per resident per day; each cell is Godot / Python.

| Season | Meals | Purchases | Hunger | Seen beliefs | Told beliefs | Gossip chats |
| --- | --- | --- | --- | --- | --- | --- |
| normal | 1.91 / 1.94 | 0.205 / 0.227 | 26.0 / 26.0 | 7.7 / 7.8 | 1.30 / 1.35 | 1.20 / 1.21 |
| scarcity | 1.89 / 1.96 | 0.251 / 0.257 | 27.4 / 25.6 | 10.6 / 8.7 | 2.01 / 1.78 | 1.57 / 1.43 |
| crisis | 1.94 / 1.91 | 0.237 / 0.249 | 26.6 / 27.6 | 9.6 / 9.2 | 2.11 / 2.10 | 1.50 / 1.46 |
| tension | 1.92 / 1.92 | 0.238 / 0.239 | 27.7 / 27.2 | 17.5 / 17.8 | 2.67 / 2.39 | 2.05 / 1.84 |

Sleep, time at home and at work, and wages match as closely (for example, tension: work 0.297 / 0.300 of
hours, wages 0.60 / 0.58).

**Violence and accidents**, across all seasons: Godot's 20 months against Python's 40.

| | Godot | Python | Per month in a town of 10 |
| --- | --- | --- | --- |
| Fights | 2 | 4 | 0.10 / 0.10 |
| Falls | 2 | 5 | 0.10 / 0.13 |
| Collisions (driven on from) | 4 (3) | 7 (4) | 0.20 / 0.18 |
| Treated at the clinic | 4 | 7 | 0.20 / 0.18 |
| Repairs | 3 | 2 | 0.15 / 0.05 |
| Found lying hurt | 1 | 2 | 0.05 / 0.05 |
| Deaths | 0 | 0 | |

- **Who comes to know of a fight:** 7 and 8 people besides those in it in Godot's crisis and tension seasons,
  against 8 and 8 in Python.
- **Harm comes to light:** every fight, fall and collision on both sides is discovered. The victim knows of it,
  someone finds them, the clinic treats them, or the debris is found.

**Thefts with the whole crime layer** (per month in a town of 10, the trading months; Godot / Python):

| Season | Thefts | Thefts discovered | Losses found | Accusations | Suspicions on the real culprit |
| --- | --- | --- | --- | --- | --- |
| normal | 1.0 / 0.8 | 100% / 100% | 1.5 / 1.4 | 1.5 / 2.1 | 68% / 23% |
| scarcity | 2.4 / 1.3 | 93% / 100% | 2.8 / 1.8 | 4.4 / 3.6 | 37% / 19% |
| crisis | 1.8 / 2.5 | 75% / 100% | 2.2 / 3.1 | 3.2 / 4.5 | 22% / 12% |
| tension | 3.0 / 2.8 | 100% / 97% | 2.8 / 3.1 | 6.8 / 5.6 | 28% / 19% |

- **Outside tolerance:** of the non-core statistics, two are: confession beliefs in the normal and scarcity
  seasons (see Known differences).
- **Speed:** 30 simulated days with the whole crime layer take 0.64-1.68 s on the Windows CI runner and 1.2 s
  on Linux.

## Results of case extraction (CI run 52)

`tools/case_reference.py` runs Python's extraction (`mystery/cases/export.py`) on 40 months (4 seasons x 10
seeds, the whole crime layer) and measures its 104 cases exactly as `case_extract.gd` (`stats`) measures Godot's
51 from 20 months. CI checks that the reference regenerates identically. The two simulations draw different
histories from the same rules, so the cases are compared by what they hold. Each cell is Godot / Python.

**What a case holds** (means per case):

| Statements | Per living resident | Summaries | Guarded | Withheld | Lies | Evasive residents | Traces (on view) | Record lines | Places refused |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 534 / 550 | 53 / 55 | 56 / 60 | 71 / 72 | 23 / 21 | 0.96 / 1.00 | 5.2 / 4.6 | 1.9 (0.39) / 2.1 (0.32) | 90 / 86 | 2.1 / 2.0 |

**Where statements come from, and how true they are** (shares of all statements but summaries):

| Saw | Told | Self | Inferred | Heard | Accurate | Mistaken | Unverifiable | Lies |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0.40 / 0.43 | 0.38 / 0.37 | 0.19 / 0.19 | 0.021 / 0.017 | 0.002 / 0.001 | 0.84 / 0.85 | 0.14 / 0.13 | 0.017 / 0.013 | 0.002 / 0.002 |

**Candidates and channels:**
- **Candidates:** 2.55 / 2.60 a month in a town of 10.
  - Thefts: 57% / 66%.
  - Ledger mistakes: 29% / 21%.
  - Collisions: 6% / 4%.
  - Fights: 4% / 4%.
  - Falls: 4% / 5%.
  - Could be playable: 67% / 74%.
- **Share of cases with at least one statement that:**
  - places the responsible person at the scene: 16% / 13%;
  - saw the act itself: 6% / 4%;
  - gives a motive: 61% / 73%;
  - shows sudden money: 29% / 29%;
  - is the culprit's lie about their movements: 45% / 48%;
  - misleads: 76% / 66%.
- **Relevance** (connected, uncertain, unrelated):
  - statements: 0.03 / 0.04 connected, 0.06 / 0.09 uncertain, 0.91 / 0.87 unrelated;
  - traces: 0.44 / 0.41 connected;
  - record lines: 0.010 / 0.020 connected.

Every core statistic (sources, statuses, statements per resident) is within tolerance, and so is every other
one but the share of cases with a motive (above). **Speed:** a 30-day month with its case candidates extracted
takes 1.0-3.8 s on the Windows CI runner, of which the simulation is about 1 s.

## Results of case generation (CI run 57)

Forty months with the whole crime layer (4 seasons x 10 seeds, 30 days, 10 residents), every candidate judged
(`test_generation.gd`). 133 Godot tests and 23,561 checks pass. The 26 pinned histories hold.

**Yield.**

| | Candidates | Eligible | Playable | Rejected |
| --- | --- | --- | --- | --- |
| Theft | 66 | 66 | 9 | 57 |
| Fight (assault) | 3 | 3 | 3 | 0 |
| Collision driven on from | 4 | 4 | 4 | 0 |
| Ledger mistake | 30 | 0 | 0 | 30 |
| Fall | 3 | 0 | 0 | 3 |
| **All** | **106** | **73** | **16** | **90** |

That is 2.65 candidates and 0.4 playable cases a month: one playable case in 6.6 candidates, one in 4.6 eligible
ones. By season, in 10 months each: tension 10, scarcity 4, crisis 1, normal 1.

**Why candidates were rejected.**

| Reason | Cases |
| --- | --- |
| Not eligible: nobody is responsible, a bookkeeping mistake | 30 |
| Not eligible: nobody is responsible, an accident | 3 |
| Theft: nobody's account of the time in question is proven false | 48 |
| Theft: the same, with at most one witness against an account (word against word) | 9 |
| The investigator's conclusion was wrong (misleading evidence), or rested on mistaken testimony | 0 |
| The package did not validate, leaked the truth, or had no hints | 0 |

**What the sealed report says of the 57 rejected thefts.** For 52, Python's truth-based suitability report finds
no route either: no one caught out, no eyewitness, no reachable trace or record pointing at the thief. Often the
thief's stash is at home behind a refusal, and nobody saw them go in. For 5, the report finds a contradiction
route. In each, the thief's account clashes with one accurate statement. The report knows that statement is
accurate; a player cannot. These are the "word against word" cases, and rejecting them is deliberate.

**False accusations: none.** In no case, eligible or not, does the investigator name anyone but the culprit:
- In all 33 ineligible cases (ledger mistakes and falls), asked anyway, it concludes nothing.
- No conclusion was rejected for being wrong.

**The playable cases.**
- **Difficulty**, from the sealed verdict: 4 gentle, 4 standard, 8 hard.
- **Routes:**
  - thefts: 5 by a record and witnesses together, 1 by a record alone, 3 by two or more witnesses;
  - fights: 2 by bad blood, 1 by a quarrel over money;
  - collisions: the damaged vehicle and the driver's deer story.
- **Effort and score:**
  - the investigator needed 221-352 questions (mean 306), 28-35 of them pressed;
  - the game scored its theory 85-100 (mean 90).
- **Every case** was played to the end as a game: found by the case library, saved and resumed, revealed, and
  the seal opened only at the reveal.

**The sealed suitability report beside Python's** (eligible cases, for reference only: different simulations,
the same rules):

| | Godot (73 eligible) | Python (77) |
| --- | --- | --- |
| obvious / playable / ambiguous / unsolvable | 5% / 12% / 45% / 37% | 3% / 16% / 51% / 31% |
| any route to the answer through evidence | 29% | 27% |
| a contradiction route | 25% | 19% |
| an eyewitness route | 10% | 9% |
| independent channels per case | 1.8 | 2.5 |
| sources of misleading information per case | 6.0 | 5.1 |

**Determinism.** The nine packages of the two pinned months are byte-identical on Windows and Linux (CI runs 55
to 57). Python's own validator reads every one.

**Quality concerns** (reported, not redesigned in this pilot):
- **Implausible alibis: in 12 of the 16 playable cases.** In every one of them it is the culprit's false
  account that puts them in the street or the square for 113 to 783 minutes, never an honest one. The liar
  stretches the place they passed through over the time of the act (pilot 4A's concern, now measured). A
  careful player may suspect the culprit from the implausibility alone, before any contradiction. That makes
  these cases easier than their label, and the lie less human.
- **Excessive irrelevant testimony: in 4 of the 16.** In each, 95% or more of the statements have nothing to do
  with the case (93-97%), or there are 700 or more of them. Across the playable cases there are 242-841
  statements (mean 513), 85% of them unrelated on average. The investigator needs about 300 questions. A person
  would need patience, or the hints.
- Every guilty driver tells the same deer story, so a collision is solved the same way each time.

## Known differences from Python

### Case generation (pilot 4B)

| Difference | Godot | Python | Why |
| --- | --- | --- | --- |
| What makes a case playable | eligible (someone genuinely responsible for a crime), and solved by the truth-blind investigator, checked against the truth afterwards | `library.py` fills slots (season, family, verdict) by the truth-based suitability verdict; ledger mistakes and falls are among the bundled cases | The brief's solvability gate: the answer must be reachable from what the player can find, and the evidence must single out the culprit. The suitability report is ported as it is, but it is sealed and decides nothing on its own. |
| Choosing among cases | every case that passes the gate is kept | `PLAN` slots, first fit by seed | Choosing which generated case to offer belongs to a future New Case flow (out of scope). |
| Case ids | `godot-` prefix | none | A Godot-made case is a different case from the Python-made one of the same seed, and must not share its save slot. |
| `generator` | `tool` "mystery (Godot)", versions "godot-native", and `options` | the Python versions | `options` records the switches the town ran with (the grocery rule among them). |
| The bundled library | unchanged, still Python-made | | |

### Case extraction (pilot 4A)

| Difference | Godot | Python | Why |
| --- | --- | --- | --- |
| Eligibility | every case says whether a playable mystery could ever be made of it, and why | every candidate may be exported, ledger mistakes and falls included | The case principles: only someone genuinely responsible for a crime makes a mystery. Python's bundled library is untouched. |
| Suitability, hints | ported in pilot 4B | `suitability.evaluate`, `hints` | |
| Where a trace can be found | the evidence audit says whether it is on view, who keeps it out of reach, whether it is on a vehicle, and who has noticed it | place, kind and source only | So pilot 4B can tell a clue the investigator can reach from one they cannot. |
| Checks | provenance of every statement, trace and record line, accounts against the presence record, lies against the history, relevance against the web, plus the spoiler boundary (with more forbidden fields) | the spoiler boundary and `check_case` | Pilot 4A's verification. |
| Reading relationships | read without creating an entry | `r.r(x)` creates a default entry | Extraction runs mid-simulation; Godot's must not change anything (and the pinned digest shows it does not). In Python it is harmless: nothing iterates relationships. |
| Versions | `godot-native` | the Python simulation's version strings | |
| Share of cases with a motive statement | 61% | 73% | The one statistic outside tolerance. More of Godot's candidates are ledger mistakes (29% against 21%), which have nobody responsible and so no motive to show. |

### In every layer: the grocery (deliberate)

| Difference | Godot | Python | Why |
| --- | --- | --- | --- |
| Shop workers serving themselves | allowed while the shop is open and nobody else is serving; at the usual price, never on credit | never: a sale needs someone else serving | Ends the grocery deadlock, in which the whole town stopped buying food for the rest of the month (29 of 320 Godot months before the fix, 21 of 320 Python months). See [The grocery deadlock fix](#the-grocery-deadlock-fix-a-deliberate-difference-from-python). |
| Shop workers buying during their shift | when their household is running short: from a colleague serving, or self-service | only by choosing to go shopping instead of working | A diligent grocer living alone otherwise seldom has food at home (pantry empty on 49% of shop days in Python, 6% in Godot). |
| Python's rule | `"shop_self_service": false` | | Kept for the comparison and the tests only: it reproduces every history pinned before the fix and replays the deadlock. Python is not changed to match. |

### With the whole crime layer (pilot 3B)

| Difference | Godot | Python | Why |
| --- | --- | --- | --- |
| The grocery stalls for the rest of the month | never, since the grocery deadlock fix; before it, 16 of 160 months with the crime layer (13 of 160 without) in a 40-town survey | 10 of 160 in the same survey (11 without the crime layer) | Before the fix, the same rule on both sides at the same rate; the towns differ, so the stalls fell in different seasons. Measured the same way on both sides (`_stall_day` in `test_sim.gd`, `stall_day` in `tools/sim_reference.py`). Since the fix, a deliberate difference: see [The grocery deadlock fix](#the-grocery-deadlock-fix-a-deliberate-difference-from-python). |
| How long someone has been missing | from when the person checking on them last saw them | the true time of death | Python writes the time of death into the carer's belief, which they cannot know. Godot uses the last time the carer saw the person (or leaves it open if they never did), so that no belief reads the truth. No event changes, only the start of that belief. |
| Repairs | 3 in 20 months: every driver who drove on | 2 in 40 months, of 4 who drove on | Rare on both sides. A guilty driver mends the damage once the vehicle is at the workshop and the repair outscores their other choices. |
| Confessions | 4 in 20 months, all after thefts | 2 in 40 months | Rare. In the normal and scarcity seasons, more of Godot's suspicions fell on the real culprit (68% and 37%, against 23% and 19%, over few accusations), and an accused culprit may confess. A confession is then told all over town, so `confession` beliefs in those two seasons are the two non-core statistics outside tolerance. |
| The intoxication noted on a collision or fall | rounded half away from zero | rounded half to even | Only the number in the event's data, and only when it ends in exactly .5. |

### With crime on, violence off (pilot 3A)

| Difference | Godot | Python | Why |
| --- | --- | --- | --- |
| Thefts that stay undiscovered | 6 of 31 | 4 of 72 | The same two reasons on both sides (CI run 34 printed each one). Four were in the last days of the month, before the tin or till was opened again. Two took a crown or two from a nearly empty household tin: when it was next opened the shortfall was under 5 crowns, put down to miscounting and written off (Python does the same with a 3-crown theft from the pub till). Python's four are three late and one tiny. Godot's thieves rob poorer tins more often: less taken per theft in most seasons (tension: 110 crowns against 384) and more attempts given up at an empty tin (next row). With 9 thefts in Godot's tension runs against Python's 24, that gives 60% discovered against 100%, the one statistic outside tolerance. |
| Attempts given up (almost all at an empty tin) | 2.6 and 4.2 a month in crisis and tension | 1.7 and 1.9 | Both sides go for a house whose people are all at work, whatever is in its tin, and give up at an empty one; Godot's thieves meet empty tins more often. Every attempt, given up or not, keeps the thief from trying again for four days, so this may also be why Godot's tension season has fewer thefts (1.8 a month against 2.4). Within tolerance. |
| Accusations | fewer in normal and tension, more in scarcity | | Follows from the number of losses found in each season (rare events: within tolerance). |
| A thief may notice the door they forced | yes | yes | Preserved as in Python: what counts as a trace of one's own wrongdoing covers the theft itself and hiding the loot, not a forced entry (whose causes are the thief's money troubles). Harmless: they know anyway. |
| Bookkeeping of a stash and of stolen food in a pantry | the thief's stash and their pantry know what is in them | the stash's and pantry's expected contents are not updated | Nobody ever counts a stash or a pantry, so nothing that happens differs. Godot updates them so that "every container holds what its owners expect, short only by what was stolen from it" can be checked for every container. |
| The `discreet` mark on events | only on discreet events | on every event (true or false) | So that the six histories pinned before Pilot 3A keep their digests. |

### Without crime (pilots 1 and 2)

All are within the test tolerance. With crime on, the first, the ledger-mistake and the violent-argument rows
below no longer apply: Godot then forms suspicions (0.07-0.32 a day), makes ledger mistakes, and fights, as
Python does.

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
| Meals in the crisis season | 1.89 | 1.51 | Explained by the grocery deadlock: 3 of Python's 10 crisis months stall (hunger standard deviation 18). Since the fix, Godot is compared with Python's trading months, and they agree (1.86 / 1.86). |
| Chats | every chat is counted | only chats that pass on gossip are logged | Since pilot 2, Godot also logs only gossip chats; the comparison counts every chat on both sides. |

**Limitations of pilot 2:**
- **Dormant suspicion pipeline, without crime.** Suspicion inference, a resident's stake in an incident, accusations, and the "nearby sightings become worth mentioning after an incident" rule have nothing to work on until something is lost or damaged. With crime on (pilot 3A) they are active.
- **Kinds of belief produced only with crime on.** Loss, damage, confession, stash and theft_self (pilot 3A); assault, injury, struck, fall, death, missing, collision_self, saw_collision, vehicle_damage and repair (pilot 3B).
- **The town's history is told once, at the start.** Old grudges and debts are known to their parties, and told to some others on Day 1 at minute 0, as in Python. The told beliefs point at the history record, not at a chat.
- **Developer-only provenance.** Beliefs are not yet visible in the game, which still plays Python-made cases. Exporting testimony from beliefs belongs to the case-packaging pilot.

## Realism concerns, shared with Python

These are Python's own rules, ported faithfully (the brief for pilot 3B: no redesign for the sake of parity). The
first two are fixed in Godot since the grocery deadlock fix, deliberately, and remain in Python. The others are
left as they are: each would change histories, so each needs a decision before it is changed.

- **The grocery can stall for the rest of the month** (fixed in Godot). On a morning the shop opens, the grocer's and the
  assistant's households may both have an empty pantry.
  - "Shop" then outscores "work". Shopping scores 25, plus 3 for every unit short of 8 per person, plus 35 for
    an empty pantry: 108 for a household of two, 84 for one person. Work scores at most 95 (75, plus up to 20
    for diligence). So a worker from a household of two always goes shopping, and one living alone usually
    does unless they are diligent.
  - Both go shopping in their own shop. Buying needs someone else serving, so neither can buy, neither counts
    as serving, and nobody else can buy either. They try again every hour, for good.
  - The town eats at the pub while money lasts, and goes hungry: mean hunger 40-58 in a stalled month, against
    about 26.
  - It happens in about 6-10% of months on both sides, most often on a Monday, after a Sunday when the shop
    is shut and pantries run down.
  - Godot now lets shop workers serve themselves when nobody else is serving, and buy during their shift.
- **A grocer living alone and keen on work never restocks their own pantry** (fixed in Godot by buying during
  the shift). They will not leave work to shop,
  and cannot buy from themselves when the assistant is out, so they eat at the pub. In Python's normal season
  such a grocer's pantry is often empty when the shop opens, in some towns on most days.
- **Every guilty driver tells the mechanic the same lie** ("Hit a deer out on the ridge road a few nights back"),
  and every repair note reads alike. That is fine for the simulation, but thin for cases.
- **Someone seriously hurt on Mill Road at night whom nobody passes gets home on their own at 10:00**, however
  bad the injury. Untreated injuries never get worse.
- **Deaths are very rare:** none in Godot's 20 months or Python's 40. Only 1.5-3.5% of fights and 8% of walkers hit
  are fatal. A case generator that wants a death will have to look through many towns or longer runs.

**In case extraction** (pilot 4A, Python's rules, ported as they are):
- **The culprit's false account can be implausible.** It stretches the place they were before the act over the
  time of it. In the CI demo (seed 1, tension) a thief says he was "at Mill Road from about 08:00" until
  "home around 18:15": ten hours on a road. A careful player can catch it, which is fair, but nobody would
  invent that. A better liar would name a believable place, ideally one with no witnesses either way.
- **Most testimony is beside the point.** A case holds about 530 statements, 91% of them unrelated to the
  incident. Summaries, topics and eras keep conversations manageable. Pilot 4B confirms that the useful channels
  can be found under the game's rules (the truth-blind investigator finds them), but at about 300 questions a
  case. See [Results of case generation](#results-of-case-generation-ci-run-57), which also measures the
  implausible false accounts: 12 of the 16 playable cases have one.
- **Small wording quirks.** "Home around 18:15 and to bed" is said of any evening at home of four hours or more.

## Next after pilot 4B

The migration is complete: a town, its cases and their investigation run in Godot with no Python, and Python
remains only as the reference and the maker of the bundled library. Recommended next, in this order:

1. **Make the false accounts believable** (case extraction, a decision on Python's rule).
   - The culprit's lie now claims hours in the street or the square in 12 of 16 playable cases.
   - It should name a believable place instead: home, or work, if they are seldom seen there. It should leave
     the clash with a witness or a record as the way to catch them.
   - This changes cases, not histories. Pinned package bytes would be re-pinned, as for the grocery fix.
2. **More playable thefts.** Only 9 of 66 thefts pass, mostly because nobody saw anything and the thief's
   account is never caught out.
   - Rather than loosening the gate, give the town honest ways to know more: a neighbour who notices a visitor
     at the house, the thief's sudden spending at the grocery, a stash a household member stumbles on.
   - Each must be a belief someone really forms in the simulation, never something added to a case.
   - The investigator's rules then use them as they are. The yield report shows the effect.
3. **Less noise.** Trim what each resident volunteers about everyday matters (meals, routine sightings far from
   the time in question), or fold more of it into summaries. Aim for the useful statements in about 100
   questions rather than 300, judged by the investigator's question count.
4. **A New Case flow** that runs a town in the background and offers the playable cases it finds, with
   difficulty, on top of `case_generate.gd` (the brief kept menus and difficulty settings out of this pilot).
5. **Vary the guilty driver's story** (the deer is the only one), so collisions are not all solved the same way.
