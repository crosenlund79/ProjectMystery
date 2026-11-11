# Prototype notes — v0.1 scaffold

These notes go with the first scaffold of the concept in [`concept.md`](concept.md) (§12, *Tomorrow's tiny
scaffold*). They record what was built, the measured results, what tuning taught us, and which open questions the
prototype answers only provisionally. None of this is a final design decision.

## What was built, against §12's minimum viable experiment

| # | §12 item | Status |
|---|---|---|
| 1 | 8–12 residents with traits, relationships, needs, economy | Done. 8 traits, trust/affection/resentment, hunger/energy/social/stress/drink, wages, rent, debts, household savings |
| 2 | 5–8 locations with movement constraints | Done. Square, Mill Road, grocery, pub, workshop, clinic, mill, plus one home per household. Moves follow the map with travel times |
| 3 | Seeded headless days with explicit state changes | Done. One-hour ticks; every change goes through events, transfers or beliefs |
| 4 | Canonical events, perceptions, beliefs, evidence | Done. See the five layers in the README |
| 5 | At least two incident families | Five: theft, bookkeeping error, assault, vehicle collision, drunken fall |
| 6 | Bookmark on an incident; export truth and player views | Done. A case is frozen 1–2 hours after someone notices (never at night) |
| 7 | Text commands for residents, topics, places, notebook, clues | Done. `investigate` REPL |
| 8 | Submit a theory; reveal the timeline | Done. Score, causal chain, every notebook entry checked |
| 9 | Optional grounded hints | Done. 3-tier ladder built only from reachable evidence channels |
| 10 | Batch many seeds with a diagnostic summary | Done. `simulate-batch`, parallel, with integrity checks per run |

## Measured results

100 seeds × 60 days × 10 residents per profile, on a 4-core container. A *case* is an incident somebody
noticed and nobody openly owned up to.

| | normal | scarcity | crisis | tension |
|---|---|---|---|---|
| Thefts per season | 1.79 | 3.41 | 4.69 | 4.90 |
| Bookkeeping errors per season | 0.74 | 0.93 | 0.88 | 0.92 |
| Assaults per season | 0.21 | 0.46 | 1.33 | 1.71 |
| Vehicle collisions per season | 0.25 | 0.31 | 0.25 | 0.47 |
| Drunken falls per season | 0.12 | 0.20 | 0.11 | 0.79 |
| Deaths (all 100 runs) | 0 | 1 | 1 | 3 |
| Runs with no incident at all | 4 | 0 | 0 | 0 |
| Runs with a major incident (injury or death) | 26 | 47 | 62 | 84 |
| Median days to first noticed incident | 12.2 | 11.6 | 7.5 | 5.9 |
| Confrontations that de-escalated | 99% | 99% | 98% | 97% |
| Cases (noticed, not owned up to) | 287 | 492 | 659 | 816 |
| … obvious / playable | 6% / 43% | 4% / 44% | 2% / 43% | 11% / 44% |
| … ambiguous / unsolvable | 25% / 27% | 22% / 29% | 27% / 27% | 17% / 28% |
| Mean independent channels per case | 2.46 | 2.36 | 2.19 | 3.05 |
| Deliberate lies in testimony | 218 | 407 | 591 | 700 |
| Sincere but mistaken statements | 13% | 13% | 14% | 14% |
| Integrity failures | 0 | 0 | 0 | 0 |
| Runtime per 100 simulated days (incl. case building) | 1.22 s | 1.61 s | 1.85 s | 2.54 s |

Notes on reading the table:

* **Integrity failures** cover location continuity, everyone being where their events say, a replay of every money
  and goods transfer, provenance for every belief, and a source event for every trace and record.
* **Playable** means at least two independent channels point at the responsible person (or, for accidents and errors,
  at the mechanism) and at least one is first-hand. That is a structural property, not proof that a human can solve the case.
  There have been no human playtests yet.
* Most night-time burglaries come out *ambiguous* or *unsolvable*. That is deliberate: a lone thief at 1 a.m. leaves
  little behind. Developer case selection (`find-case`) exists so a playable case can be picked without touching history.
* "Mistaken testimony" counts sincere errors only: rumours that drift in time, wrong suspicions, misremembered times,
  misidentification in the dark, and people repeating a lie they were told. Deliberate lies are counted separately.

## What tuning taught us

The first runs were a crime wave: about 6 assaults and 7 thefts per normal town per season. Each fix below
targets a mechanism, not a probability.

1. **Households pool money.** One unemployed resident went broke while their spouse, the grocer, held 700 crowns.
   That one resident committed 14 thefts and took 25 loans. Real households share a savings tin, so now
   they do.
2. **Businesses must be solvent.** The grocer skimmed the till so low that deliveries couldn't be paid, so the town
   ran out of food. The pub lost money every day because almost nobody drank, so it couldn't pay its barhand.
   Fixes: a till float, owners covering shortfalls from their own pocket, and socialising at the pub sometimes
   including a drink.
3. **Old grudges only flare with drink and opportunity.** Otherwise people walked across town every other day
   to confront the same old enemy.
4. **Money arguments need an off-ramp.** A promise to pay with a new date now ends most debt arguments.
   97–99% of confrontations end without violence, depending on the profile.
5. **Lenders hear about other debts.** Without that, one borrower could cycle through every neighbour.
6. **Customers leave at closing time.** One thief was locked inside the pub and "forced" the door from the inside.
7. **Independence follows the original source.** Nine people repeating one rumour first counted as nine witnesses.
   Channels are now grouped by whoever actually perceived the thing.
8. **Natural channels for night thefts.** Housemates who wake to hear the door, and creditors who are suddenly
   repaid in full, are realistic ways a lone thief gets noticed.
9. **A killer doesn't find the body.** Missing people get checked on by whoever cares most about them, and bodies
   are eventually buried.
10. **Within-the-hour ordering.** In 2 of 100 crisis runs, an action timestamp came after a death processed
    earlier in the same hour, so a victim "ate" after dying. The integrity checks caught it. Action minutes now
    follow processing order.

## Provisional answers to the open questions (§15)

These are v0 choices made to get a playable loop, not decisions.

1. **Who is the player?** A local who has just returned after months away. They have no pre-case knowledge to
   reconcile and no official power.
2. **"Living there".** The game starts at the investigative moment; daily life before it is simulated, not played.
3. **How many residents?** 10 by default (8–12 supported). Ten already produce 5–10k beliefs per season; testimony
   volume, not simulation cost, is the limit.
4. **Rare crimes.** Pressure profiles plus explicit developer case selection. Batch reports state the real rates.
5. **What counts as solving?** The score covers explanation (40), responsibility (30), motive (10) and cited
   evidence (up to 20), minus 5 per hint credit. "Unresolved" earns 50 when the evidence really was thin, 15 otherwise.
6. **Does the world move during an investigation?** No. The case is frozen at its start.
7. **Access.** Public places are open. Homes, back rooms and record books need the owner's consent, and refusing is
   itself a clue (people hiding something refuse, but so do very private households).
8. **Lying and withholding.** The responsible person lies about their whereabouts (unless the act was witnessed), invents
   an explanation for damage, or claims the other person started a fight. Loyalty to family and low confidence make
   statements *guarded* (shown only when pressed, which costs goodwill). Nervous, honest people visibly hesitate;
   smooth liars don't.
9. **What is a hint worth?** 6 credits per case; nudge 1, lead 2, strong hint 3; each credit costs 5 points.
10. **Legal setting.** None yet; no courts or police.
11. **Independent but understandable residents.** The reveal shows the causal chain: refused loans, overdue debts,
    rent missed, the walk across the square, the forced door.
12. **Language models.** None. All text is templated from structured beliefs, so facts can't drift.

## Known limitations

* Time and space are coarse: one-hour ticks, a fixed graph, no line of sight or windows. Sightings happen only on the
  square and Mill Road or inside the same building.
* Testimony is template text and can be repetitive; presence lines are grouped to keep answers readable.
* `investigation.json` holds every answer a resident *would* give and the hint ladder. It never contains the
  truth, but reading the file directly spoils the puzzle.
* A body hidden somewhere other than the victim's home could stay unfound. There is no missing-person case type yet.
* Suitability and hint heuristics are first-pass and untested with human players.
* Crisis and tension are harsh (about 1.3 and 1.7 assaults per season in a town of ten). Whether that is credible needs the research program in §10.
* Seeds are stable only within the same `SIM_VERSION`/`CONFIG_VERSION`. README examples will drift as the
  simulation changes.

## Suggested next steps

1. Human playtests on a handful of `playable` cases per family. Record solve rate, hint use and confidence. Use
   those results to calibrate the suitability verdicts.
2. A missing-person case type, and bodies that can be moved or hidden (a cover-up family).
3. Richer perception: windows, sound through walls with distance, weather and lighting.
4. Let the investigation itself have consequences: residents hear they were asked about, and suspects react.
5. Begin the research program (§10): build causal case maps from documented real cases. Compare escalation and
   de-escalation rates with what the profiles produce.
