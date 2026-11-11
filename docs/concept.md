# Project Mystery

> **GameSeedVault — exploratory concept and first-prototype blueprint**  
> **Working title:** Project Mystery (placeholder, not a final game title)  
> **Status:** Exploring → candidate for a small experimental scaffold  
> **Genre collision:** Autonomous social simulation × investigative mystery  
> **Core promise:** *A small town lives its own life. Something happens. You must reconstruct the truth from what its residents actually know and what the world actually preserved.*

---

## 1. The idea in one paragraph

The player lives in or belongs to a **small, isolated town** with a **very limited population**. Its residents are autonomous, relatively competent AI characters with routines, needs, resources, relationships, secrets, personalities, and imperfect knowledge. Before a case begins, the town is simulated forward: people work, borrow money, argue, reconcile, make mistakes, lie, help each other, and occasionally cause serious incidents. The simulation records an immutable *objective history*. The player then enters the **same world after an incident**, with that history hidden, to question residents, explore topics, examine evidence, test hypotheses, and decide what happened. The mystery is not a prewritten script: it is an outcome of the social simulation. The game must be able to show the actual timeline afterward so we can check whether the mystery was fair and solvable.

### The spark

This concept began as *colony simulator × detective game*, then changed direction decisively:

- **No colony management.** The player does not assign jobs, build houses, or manage production.
- **Small and intimate, not sprawling.** A handful of people, a finite community, and relationships that matter.
- **People first, crimes second.** The system should simulate believable lives, not mechanically spawn a murder every few days.
- **Investigation is reconstruction.** The player is trying to establish what actually happened, not click through a prescribed sequence of clues.
- **The player should be able to be wrong.** An accusation can be plausible and still be mistaken.

The initial prototype is intentionally **text-only, with no graphics or content-production burden**.

---

## 2. The fantasy and emotional tone

Imagine knowing the butcher, the mechanic, the pub owner, the teacher, and the couple who never quite get along. Everyone has a routine. Everyone has opinions. People remember favors and insults. Rumors travel differently through different relationships. An argument that one person witnesses directly may become a completely different story by the time it reaches somebody else.

Then something disruptive happens: missing supplies, a disappearance, a car accident, a theft, a suspicious injury, or perhaps a killing. There might not even be a crime. The player is not guaranteed an obvious culprit, nor a tidy answer.

The intended feeling is **curiosity → suspicion → reconstruction → doubt → revelation**, grounded in a town that feels inhabited rather than a puzzle board arranged for the player.

**Important distinction:** the dramatic event is not necessarily murder. We want the ability for murder to arise sometimes, but we do not want to force one into every run.

---

## 3. Pillars — what makes this concept itself

1. **Causal truth.** Every significant event has a cause, time, location, participants, and consequences. The authoritative simulation knows what happened.
2. **Limited perception.** Residents know only what they experienced, inferred, were told, or misremembered. They cannot truthfully testify to unseen events.
3. **Autonomous lives.** Residents pursue their own short- and long-term goals; they are not puppets waiting to trigger plot beats.
4. **Consequences, not scripts.** Debt, isolation, alcohol, scarcity, fear, jealousy, misunderstandings, and opportunity can combine into unexpected events.
5. **Honest mysteries.** Clues must come from actual simulated states and actions, not be invented retroactively to support a preferred solution.
6. **Investigative freedom.** The player explores people, places, objects, timelines, claims, and topics in their own order.
7. **Auditable outcomes.** Every case can be replayed and compared with the sealed truth for debugging and post-case learning.

### Things this is *not*

- Not a colony-management game.
- Not an endless stream of scripted murder cases.
- Not an AI chatbot that improvises a different truth whenever questioned.
- Not a guarantee that every suspicious event ends in a conviction.
- Not initially a graphics-heavy RPG, open-world game, or complete courtroom simulator.

---

## 4. The two-stage experience

### Stage A — The town lives (simulation / case generation)

1. Create a seeded small town, its places, resident relationships, possessions, finances, and initial conditions.
2. Simulate days or weeks rapidly, with no player intervention required.
3. Let residents make decisions and interact according to consistent world rules.
4. Record the complete objective event timeline, state changes, and each resident's separate knowledge.
5. Detect noteworthy incidents: crimes, accidents, disappearances, disputes, losses, cover-ups, or serious changes in relationships.
6. Assess whether an incident offers a potentially interesting and *investigable* case.
7. Save an immutable case snapshot and keep the truth behind a spoiler boundary.

A run with no major incident is a valid simulation result. For playtesting, the developer may run many seeds or increase environmental stress to find interesting cases; that must be an explicit testing mode, not a disguised claim that the world is fully spontaneous.

### Stage B — The player investigates (same world, limited knowledge)

1. The player enters the town **after the simulated events**. The pre-incident history is fixed and does not regenerate.
2. The player receives only a plausible starting point: a concern, rumor, report, missing person, or discovered incident.
3. The player interviews residents, revisits earlier statements, inspects locations and objects, asks about specific people, dates, debts, movements, and conflicts.
4. Answers depend on what the NPC perceived, remembers, believes, and wishes to disclose.
5. The player keeps notes, compares accounts, identifies contradictions, and forms hypotheses.
6. The player can conclude with a theory, identify a suspect, decline to accuse, or mark a case unresolved.
7. After submission or explicit surrender, a **Reveal the Truth** option displays the actual timeline alongside the player's reconstruction.

**One history, two viewpoints:** “another timeline” means another *perspective on the same events*, not an independently rerolled past. If the world continues during the investigation, new events are appended; the prior history remains immutable.

### The player's place in town — open question

The preferred fantasy is **living in the isolated community**, not automatically being a police officer. For the first prototype, the player can be a local resident who was uninvolved in the simulated incident, or simply an abstract investigator with limited access. Decide later how the player's pre-case whereabouts and prior knowledge are established without inconsistency.

---

## 5. The town as a simulation

### Proposed initial scale (prototype targets, not locked game limits)

| Element | First experiment | Later potential |
|---|---|---|
| Residents | 8–12 | 15–30, only if performance and coherence hold |
| Locations | 5–8 named locations | Homes, shops, pub, clinic, workshop, surrounding roads |
| Simulated time | 20–100 days, accelerated | Long-term histories and persistent campaigns |
| Detail level | Text, structured events, coarse time steps | Fine-grained movement, schedules, environment |
| Incidents | Theft, conflict, accident, possible escalation | Broad range of organic incidents and crimes |
| Player interface | Terminal or minimal local UI | Richer dialogue, evidence board, map, presentation |

### Resident model

Each resident should initially have:

- **Identity:** name, age category, occupation, household, home and workplace.
- **Traits:** e.g. impulsiveness, caution, empathy, stubbornness, sociability, honesty; not crude moral labels such as “born murderer.”
- **Needs and pressures:** money, food/supplies, safety, rest, social connection, stress.
- **Resources:** wages, savings, debt, goods, vehicle access, possessions.
- **Relationships:** trust, affection, resentment, obligation, fear, friendship, family connections.
- **Goals:** obtain food, earn income, pay debt, protect a friend, rest, seek help, avoid exposure, resolve conflict.
- **Schedule and location:** enough spatial and temporal consistency to make whereabouts meaningful.
- **Memory and knowledge:** observed events, information received, confidence, source, time of acquisition, possible distortion.
- **Recent history:** major events that influence future decisions.

NPCs should show basic competence: seek reasonable ways to address needs; avoid impossible travel; avoid knowing secrets by magic; consider consequences; sometimes make poor decisions under pressure. A character can be impulsive or dishonest without behaving randomly.

### Decision making: sensible first approach

Start with **structured goals + utility scoring / simple planning**, not one expensive free-form language-model call per resident per minute. A decision considers current needs, goals, opportunities, relationships, perceived risks, and available actions. Introduce bounded randomness for variety and deterministic seed replay.

LLMs may later help express conversations naturally or choose among constrained dialogue intents, but they must **not** create world facts, silently rewrite timelines, or invent evidence. Any free-text answer must be grounded in an NPC's actual knowledge and the current investigation state.

---

## 6. The incident engine: pressure, opportunity, choice, consequence

The model should not contain a simplistic rule like `stress > 80 ⇒ murder`. Instead, pressure changes priorities and acceptable risks, while environment and relationships determine available choices.

### Candidate pressures to experiment with

| Pressure | Possible developments (not guaranteed) |
|---|---|
| Debt / running out of money | Ask for help → borrow → conceal a problem → theft or fraud → dispute |
| Food or supply shortages | Negotiate → borrow supplies → hoard → steal → accusation or conflict |
| Alcohol / impaired judgment | Miss obligations → argument → impaired driving → accident → panic or concealment |
| Relationship fracture | Withdrawal → jealousy → confrontation → separation or reconciliation |
| Fear of discovery | Evasion → false statement → evidence tampering → escalating conflict |
| Isolation / exhaustion | Poor judgment → neglected responsibilities → misunderstandings → mistakes |
| Reputation and rumors | Suspicion spreads → exclusion → retaliation, or cooperation and correction |

Residents must also have **nonviolent off-ramps**: apologies, financial help, asking for supplies, leaving a conflict, reporting an offense, repairing harm. If every crisis becomes violence, the simulation has failed.

### Distinguish outcomes

An event can be an accident, reckless act, intentional crime, misunderstanding, or entirely lawful conduct. The simulator should know intent as part of the character's decision context; an investigator cannot infer legal guilt from a tragic result alone.

### How to make rare events testable without faking them

Provide explicit developer controls to:

- Choose simulation seed and initial conditions.
- Set stress/environment profiles: normal, scarcity, economic crisis, high tension, etc.
- Run hundreds or thousands of headless trials and record incident rates.
- Select a case with genuinely discoverable evidence, without modifying its already-generated past.
- Reproduce any chosen run from seed and event log.

**Design tension:** A credible sandbox might generate serious violence rarely. A playable mystery generator needs interesting cases with useful frequency. Solve this transparently through scenario conditioning, case selection, and later balancing—not by pretending every run naturally yields murder.

---

## 7. The truth, knowledge, testimony, and evidence layers

The most important technical boundary in the project is separating these layers.

### A. Objective history — authoritative, sealed

A canonical event record holds the facts of every consequential action: who, what, when, where, involved objects, preconditions, effects, and causal links. It is not shown during an active case.

### B. Perception — what could physically be noticed

For each potential observer, evaluate time, location, distance, visibility, obstruction, audibility, distraction, and attention. The resident may see part of an interaction, hear a noise without seeing its source, or miss an event entirely.

**Rule:** an NPC cannot truthfully know a fact just because it exists in the authoritative event log.

### C. Belief and memory — what the resident thinks happened

Store each remembered claim with provenance: direct observation, inference, or secondhand report; timestamp; confidence; uncertainty; and any later update. Residents may draw mistaken conclusions, misremember, repeat rumors, deliberately conceal information, or lie. Model those separately—**being mistaken is not the same as lying**.

### D. Physical evidence — consequences of world actions

Objects and traces must arise from interactions: a moved item, missing money, damaged door, broken lamp, vehicle damage, store records, an object left somewhere. Avoid “spawn a bloodstain because the puzzle needs a clue.” Evidence can be lost, contaminated, overlooked, or explained innocently, subject to explicit rules.

### E. Player knowledge — what has been discovered

Maintain discovered testimony, evidence, observations, contradictions, notes and hypotheses **separately from objective truth**. The player can know less, be misled, or reach a reasonable but wrong conclusion.

### Simple event / knowledge example (illustrative)

```text
TRUTH — 19:12  Daniel argues with Margaret outside the shop.
TRUTH — 19:13  Elias, behind a wall, hears raised voices.
PERCEPTION     Elias hears shouting, but cannot identify both speakers.
BELIEF         Later, Elias hears that Daniel owes Margaret money.
TESTIMONY      Elias says: "I think it was Daniel arguing with her."
PLAYER         Can compare his account with others; cannot see TRUTH yet.
```

To keep cases fair, testimony should distinguish *“I saw”*, *“I heard”*, *“I think”*, and *“someone told me”*. Even deliberately unreliable testimony must have an explainable source in the agent's state.

---

## 8. Investigation mechanics — text first

### Starting interaction model

A minimalist investigation screen or command-line interface could offer:

- **People:** list known residents; speak with one; revisit previous conversation.
- **Topics:** recent events, relationships, money, whereabouts, rumors, people, dates, objects.
- **Places:** inspect a shop, home, road, pub, workshop, or incident location if access is justified.
- **Evidence:** inspect discovered objects and records; view how/where an item was found.
- **Timeline:** maintain a player-built timeline containing only discovered or hypothesized facts.
- **Notebook:** mark claims as confirmed, disputed, uncertain, or your own inference.
- **Theory:** submit a reconstruction with actors, motive (if known), event order, and evidence.
- **Case outcome:** accusation, no-crime conclusion, unknown, or unresolved.

Topics should not be fixed magic keywords that reveal plot solutions. A resident's available responses depend on their actual knowledge and willingness to share it; the interface may use selectable topics rather than unrestricted natural language for v0.

### Example illustrative interaction

```text
CASE: The Closed Grocery
Day 19 — Morning

Known: Margaret has not opened her shop.

[1] Speak to Daniel
[2] Speak to Elias
[3] Inspect the grocery
[4] Review notebook
[5] Ask for a hint
[6] Submit theory

> 2

ELIAS — What would you like to ask about?
  A. Last night's shouting
  B. Daniel's whereabouts
  C. Margaret's recent troubles

> A

"I heard an argument around seven. Couldn't make out much."

Notebook updated: Elias heard raised voices; identity unconfirmed.
```

This is an **interface sketch**, not a predetermined case or promised dialogue.

### Hint system — explicitly optional

The player can buy progressively stronger hints using **in-game investigation credits** (not real-money payments). Potential tiers:

1. **Nudge:** draw attention to a neglected topic or inconsistency.
2. **Lead:** suggest a useful person, time window, or location.
3. **Strong hint:** identify a meaningful contradiction or missing connection.

Hints must be derived from *actual, currently discoverable facts* in the sealed case and must never invent clues or spoil the full answer by default. Track hint use when scoring. Whether credits are fixed per case, earned through progress, or replenished is unresolved.

---

## 9. Solvability: harder than generating a dramatic event

A town might generate a perfectly plausible accident with **no surviving evidence**. That is a legitimate historical outcome but may be a poor playable mystery. Therefore, keep these two questions separate:

1. **Did an interesting event occur?**
2. **Can a player reasonably infer anything useful about it?**

A case suitability evaluator could inspect:

- Is there a clear incident that someone in the town would notice?
- Are there independent evidence channels (physical traces, documents, observations, testimony)?
- Does the relevant evidence survive to the investigation start?
- Is it accessible without omniscient knowledge or impossible leaps?
- Can plausible alternate explanations be tested rather than arbitrarily dismissed?
- Does the system correctly allow *unresolved* when proof is insufficient?

Do **not** demand that every case has one discoverable, legally provable perpetrator. Some cases can remain ambiguous; the player should be allowed to recognize uncertainty.

### Three complementary measures of success

- **Simulation credibility:** resident decisions and event chains make sense in retrospect.
- **Evidence integrity:** all clues, statements, and times are consistent with the world and NPC knowledge rules.
- **Playability:** a careful investigator can make meaningful progress without requiring knowledge of the hidden log.

---

## 10. Research program (before claiming realism)

The long-term design needs research into real-world chains of events and how investigations succeed or fail. We should avoid treating television crime logic as evidence about real cases.

### Research areas

| Area | Questions for the simulation |
|---|---|
| Social conflict and escalation | How do debt, perceived betrayal, loss, stress, and opportunity affect choices? What de-escalates disputes? |
| Accidents and impulsive actions | How do risky acts differ from intentional harm? What circumstances lead to concealment or admission? |
| Eyewitness perception and memory | What can someone see or hear? How do delay, suggestion, confidence, and rumor affect accounts? |
| Investigative methods | How do investigators build a timeline, corroborate accounts, preserve evidence, and test alternative hypotheses? |
| Physical and documentary evidence | Which traces are naturally produced, how long do they persist, and how can they be misinterpreted? |
| Wrongful accusation and conviction | How can individually weak pieces of evidence combine into an apparently persuasive but false story? |
| Legal reasoning | What distinguishes suspicion, reasonable inference, charging, and conviction in a selected jurisdiction? |
| Multi-agent simulation | Which planning, memory, relationship, and belief models produce coherent autonomous behavior at low cost? |

### Suggested methodology

Use documented real cases from reliable primary or research sources where possible. For each case, build a structured **causal case map**: preceding pressures → key decisions → objective events → observers → physical traces → claims → investigative actions → evidence assessment → outcome. Include accidents, acquittals, unsolved cases, and wrongful convictions, not only clear homicides.

A legal verdict is not an omniscient truth detector. Courts have evidentiary rules and standards of proof, which vary by jurisdiction; any eventual courtroom system should be researched and deliberately scoped rather than improvised.

Comparable inspirations worth analyzing (not copying): **Shadows of Doubt** for simulated citizens and procedural investigation; **Generative Agents** research for memory/planning/reflection; selected detective games for note-taking and inference design. Research findings should be documented separately from fictionalized game rules.

---

## 11. Development architecture (suggested)

For the no-graphics prototype, favor a simple **headless simulation core + text interface**. A lightweight Python CLI is a practical option for running many deterministic trials quickly; Godot can remain a later presentation layer. The language is a tooling choice, not a final product decision.

### Logical modules

```text
project-mystery/
├── README.md
├── config/                 # Town presets, resident templates, tuning
├── sim/
│   ├── world.*             # Locations, time, inventory, finances
│   ├── residents.*         # Needs, traits, relationships, goals
│   ├── decisions.*         # Action selection and constraints
│   ├── events.*            # Canonical actions and consequences
│   ├── perception.*        # Who could observe what
│   ├── memory.*            # Beliefs, testimony sources, uncertainty
│   └── incidents.*         # Incident detection and classification
├── cases/
│   ├── export.*            # Frozen snapshots and spoiler-safe views
│   └── suitability.*       # Investigability checks
├── investigate/
│   ├── dialogue.*          # Topic-based questioning
│   ├── evidence.*          # Discoverable objects and records
│   ├── notebook.*          # Player-known timeline and hypotheses
│   ├── hints.*             # Grounded progressive hints
│   └── verdict.*           # Submit theory / reveal truth
├── tests/                  # Unit, property, replay, batch and playtests
└── runs/                   # Generated case data (not necessarily in Git)
```

### Recommended data contracts

Every significant event should carry a **stable event ID**, simulation timestamp, location, actors, action type, preconditions/effects, and causal references. Every memory/claim should point to its origin event or source claim when known. Every evidence item should reference the world action that created or changed it, with discovery rules.

Save a seed, configuration version, simulation version, and canonical event log for every run. Deterministic replay is only guaranteed when these versions and all randomness are controlled; don't rely on the seed alone if model behavior or rules change.

### Spoiler separation

Export two separate views:

- `truth` / developer-only: complete timeline, motivations, agent private states, event provenance.
- `investigation` / player-safe: starting context, currently discoverable objects, permitted dialogue, revealed knowledge, notebook.

The player UI must never read or render hidden truth directly. A separate reveal operation should be explicit, irreversible for the current spoiler-free run, and accessible after conclusion or surrender.

---

## 12. Tomorrow's tiny scaffold — bounded and testable

**Goal:** Prove that a small, auditable simulation can generate an incident and support a coherent text-only investigation of it. This is **not** a commitment to build the full game tomorrow.

### Minimum viable experiment

1. Generate **8–12** residents with a few traits, relationships, daily needs, and economic conditions.
2. Create **5–8** locations and simple movement/scheduling constraints.
3. Simulate days headlessly with seeded random decisions and explicit state changes.
4. Record canonical events, each NPC's perceptions, beliefs, and evidence consequences.
5. Implement **at least two incident families**, e.g. a resource-related theft and a vehicle accident or serious interpersonal dispute. Murder is an emergent stretch goal, not a test prerequisite.
6. Stop or bookmark a run when a notable incident occurs; export both truth and player-safe case data.
7. Provide simple text commands to inspect residents, topics, places, notebook, and available clues.
8. Let the player submit a theory and reveal the objective timeline for comparison.
9. Add a basic optional hint mechanism grounded in case data.
10. Batch-run many seeds and produce a diagnostic summary of incidents and integrity failures.

### Suggested developer commands (illustrative)

```text
simulate --seed 48291 --days 60 --profile normal
simulate-batch --runs 1000 --days 60 --profile scarcity
list-incidents --run 48291
export-case --run 48291 --incident 3
investigate --case <case-id>
reveal --case <case-id>
replay --seed 48291
```

Command names are examples, not a mandated CLI.

### Essential acceptance checks

- [ ] Same seed **and same code/config versions** reproduce the same objective timeline.
- [ ] No resident appears at two incompatible places at the same time.
- [ ] No resident spends goods or money they do not have, unless an explicit debt/credit rule permits it.
- [ ] An NPC's truthful statement is traceable to direct perception or explicitly identified secondhand knowledge.
- [ ] NPC memory can be mistaken without changing objective history.
- [ ] Evidence is generated by world events, not inserted retroactively for puzzle convenience.
- [ ] The player's view cannot access the sealed objective log during investigation.
- [ ] A case can resolve to **accident**, **no crime**, or **unresolved**, not only culprit found.
- [ ] At least one seeded incident can be investigated from start to submitted theory to truth reveal.
- [ ] A batch report distinguishes no-incident runs, major incidents, candidate cases, and suitable playable cases.

### Measurements worth collecting

- Runtime per 100 simulated days; event count; memory footprint.
- Frequency and type of incidents by profile.
- Distribution of time before first notable incident.
- How often conflicts de-escalate rather than worsen.
- Contradictions between world state and testimony, separated from *intentional* misinformation.
- Number of independent evidence sources per case.
- Percentage of cases marked playable, ambiguous, or unsolvable.
- Human playtest success, uncertainty, and hint usage.

**Warning against metric gaming:** A high murder rate is not evidence of better AI. Neither is a high case-solve rate proof of a believable mystery. Inspect actual event logs and causality.

---

## 13. Example hypothetical case chain

*Illustrative only; this is not an approved scripted story, and the prototype must not hardcode this chain.*

1. A shopkeeper struggles to pay a supplier.
2. A neighbor refuses a loan.
3. The shopkeeper takes supplies without permission.
4. A third resident sees the shopkeeper near the premises but not the theft.
5. Rumors spread, and a confrontation follows.
6. Later, a separate incident occurs involving a vehicle at night.
7. One witness hears an impact but sees no driver.
8. An uninvolved resident becomes the leading suspect because of an earlier public argument.
9. A trace on the vehicle and a contradictory statement may—or may not—clarify events.

The player should have to distinguish **motive from proof, coincidence from cause, and belief from observation**. The simulation may also produce a mundane resolution, reconciliation, or no serious crime at all.

---

## 14. Roadmap — possibilities, not promises

| Stage | Focus | Exit condition |
|---|---|---|
| **0 — Simulation laboratory** | Text-only town, autonomous decisions, event log, batch seeds | Coherent repeatable social histories |
| **1 — First case** | Incident detection, sealed truth, inquiry topics, evidence, theory submission | A human can investigate one generated case |
| **2 — Reliable mystery generation** | Better evidence sufficiency, rumors, uncertainty, hints, multiple incident types | Repeated runs produce varied *fair* cases |
| **3 — Richer social model** | Longer memories, shifting relationships, reputations, evolving goals | Residents feel consistent across time |
| **4 — Full game decisions** | Player role, long-term town life, world presentation, legal consequences | Explicit design approval before major expansion |

Possible later features **not yet approved**: natural-language questioning, persistent player relationships, detailed forensics, formal police/court proceedings, dynamic media/radio, physical exploration, or graphics. Each introduces significant scope and needs its own justification.

---

## 15. Open design questions

These remain genuinely undecided:

1. **Who is the player?** Ordinary resident, newcomer, informal investigator, constable, or a role chosen later?
2. **What does “living there” mean?** Are we playing daily life before the incident, or beginning at an investigative moment with believable prior local ties?
3. **How many residents are enough** to generate depth without overwhelming simulation and investigation?
4. **How rare should serious crimes be**, and how should a game find an engaging case without misrepresenting the simulation?
5. **What counts as solving a case?** Correct sequence of events, accurate culprit, well-supported theory, or a cautious acknowledgement of uncertainty?
6. **Can cases continue to evolve** while the player investigates, and how can that remain fair?
7. **How should player access work?** Can a civilian inspect private homes or financial records? What are the social and legal consequences?
8. **How much should residents lie, infer, forget or refuse**, and how can this be readable rather than frustrating?
9. **What is a hint worth?** Limited per-case credits, a cost to score, or another in-game resource?
10. **What legal setting and era** should govern investigations and potential convictions?
11. **How do we keep residents independent** while still making their actions understandable to the player?
12. **How far should AI language generation go**, given cost, consistency, and the requirement that facts remain immutable?

---

## 16. Scope guardrails and project relationship

**Project Mystery is a GameSeedVault concept.** It is separate from Ember & Ash and does not replace or redirect that project. Its first proposed experiment is deliberately small, text-only, and designed to answer a research question: *Can a socially simulated town produce meaningful, investigateable events?*

Do not start by building art, a giant map, a full police department, dozens of criminal systems, or free-form LLM conversations. Prove causality, perception, investigation, and testability first.

### One-sentence north star

> **Build a town that produces true histories—and let the player discover how difficult it is to know the truth.**

---

*This document captures a creative design direction, proposed experiments, and unresolved decisions. It is not a claim that any systems have been implemented, tested, or approved for full production.*
