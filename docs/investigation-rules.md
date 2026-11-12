# Investigation rules: the contract shared by Python and Godot

The rules of play are implemented twice, so the game runs without Python:

* **Python reference:** `mystery/investigate/{dialogue,notebook,session,verdict}.py`, through the structured
  `*_result()` methods and `reveal_model()`.
* **Godot game:** `godot/scripts/core/investigation.gd` and `verdict.gd`.

Both must give identical structured results for the same actions on the same case. That is enforced by
**parity fixtures**: scripted investigations that `python -m mystery build-library --parity
godot/tests/parity` records from the Python engine. They cover every incident family. `godot/tests/test_parity.gd`
replays each action in Godot and requires an exact match, step by step, from the first answer to the last
line of the reveal. `tests/test_package.py` checks that the fixtures still match the current Python rules.

Times are minutes since Day 1 00:00. "Entries" are notebook entries.

## Questioning: `ask(resident, topic, press, follow)`

* Topics are the eight base topics (`whereabouts`, `window`, `incident`, `money`, `conflicts`, `rumors`,
  `vehicles`, `past`) plus `person:<id>` for every other resident.
* The dead cannot answer: `{"dead": true, "lines": [["<First> is dead."]]}`.
* **Patience:** each resident starts with `goodwill` from the case. Pressing costs 1. A topic can be pressed
  once. At 0 patience, pressing returns *"That's enough questions for today. I've told you what I know."*
* **What is said:** the items whose `topics` include the topic, except the ones *behind* a summary told on
  that topic (an item with `in` whose front item has the topic). Guarded items are included only once the
  topic has been pressed. The rest are sorted by `(time is null, time or 0, key)`.
* **Recent first:** unless the topic is `incident` or `past`, a question covers items without `era`. The items
  with `era: "earlier"` are told on the follow-up `earlier`.
* **Follow-ups** (`follow`; free, and never together with `press`):
  * `"more"` ("Tell me more", or "Can you be more exact?" for whereabouts) tells the items behind the
    summaries in reach that are not in the notebook yet. Summaries told on recent times are always in reach;
    earlier ones once `earlier` has been asked on that topic. If there is nothing new: *"That's about all
    there is to it."*
  * `"earlier"` records the topic in `state.earlier[resident]` and tells the earlier items, with guarded ones
    once pressed. If there are none: *"I can't think of anything before that."* (or the evasive line if only
    guarded ones remain).
  * A first question that finds nothing recent while earlier items exist answers *"Nothing lately that I know
    of."*
* The result's `can_more` is true when `more` would tell something new. `can_earlier` is true when the topic
  has earlier items and `earlier` has not been asked on it.
* **Grouping:** consecutive items with the same `group.id` become one line: the group template with names
  joined as "A, B and C", each name once. All of their entries are recorded.
* **Nothing to say:** if the resident is withholding on the topic (`evasive_topics`) or has guarded items,
  they give their style's evasive line. Nervous: *"I... I'd rather not get into that."* Smooth: *"Can't help
  you there, I'm afraid."* Otherwise they say *"I don't know anything about that."*
* **Holding back:** if guarded items remain hidden, a nervous resident adds *"(They hesitate, as if there is
  something more they are not saying.)"* Smooth liars give no tell.
* **Pressing in vain:** pressing a topic that has no guarded items adds *"(Pressing them doesn't get you
  anything more.)"*
* Every statement heard becomes entry `S<n>` with text `First: "statement"`, its time and speaker, unless
  it was heard before.
* The result also gives `follow`, `goodwill`, `can_press` (the topic is not yet pressed and patience is above
  0), `can_more`, `can_earlier` and `followups` (the sorted ids of people the statements mention).

## Looking around

* **`inspect_place(id)`:** if not `allowed`, the result is the owner's reply and an observation entry
  `O<n>` *"Refused entry to …"*, with no traces. If allowed, each trace becomes `X<n>` *"At <place>:
  <description>"*. The result lists the record books kept there and the vehicles parked there. The owner's
  reply is shown when the place has owners.
* **`inspect_vehicle(id)`:** the same, with `O` *"Not allowed to look at …"* or `X` entries (the description
  alone).
* **`read(book, day)`:** if refused, `O` *"Not allowed to read the …"*. If allowed, the entries (optionally
  one day's) and an `O` *"Read the <title>[ for Day N]"* entry, filed under the reference `read:<book>:<day or None>`.
* **`cite_record(entry_id)`:** copies a line from an open book into the notebook as `D<n>`.
* **`note(text, time)`:** the player's own note `N<n>`, optionally placed on the timeline.
* **`mark(entry, mark)`:** `confirmed`, `disputed`, `uncertain` or `inference`. Anything else is refused.

The notebook never holds the same reference twice. Entry ids are a prefix letter plus a running number per
prefix, and the numbering survives saving and loading.

## The town (Godot only)

The Godot game adds a world layer on top of these rules: `godot/scripts/core/town.gd`. The Python text game
has no town, so this part has no parity fixtures. It changes where you can act, never what an action returns.

* **Where people are:** each resident is at `now_at` for the whole investigation (time is frozen). In a package
  without it, everyone is at home. The dead are nowhere.
* **Moving:** `go(place)` takes you there, marks it visited, and records everyone present as seen there.
  You start in the square.
* **Finding someone:** `find(resident)` goes to where you saw them. If you have not seen them, it tries their
  home and says when they are not in.
* **Acting where you are:**
  * `ask` needs the person present;
  * `read` needs you at the place where the book is kept (`records[book].place`);
  * `examine` needs you where the vehicle is parked;
  * `look_around` inspects the place you are at.
  Otherwise each call delegates to the rules above unchanged, with the same results and the same notebook.

## Evidence management and Hobby Detective (Godot only)

* **Statuses:** `set_status(entry, status)` marks any notebook entry `suspicious`, `active` or `ignored`, and
  `""` clears it.
  * Statuses are saved with the case.
  * Ignoring only hides an entry from the default views (Review ignored shows it). Nothing is ever deleted.
* **Mode:** each case is played as Normal Detective or Hobby Detective. The mode is chosen on the New Case
  screen, fixed when the case starts, and saved with it.
* **`check(entry)`, Hobby Detective only:**
  * Only statements, traces and record lines can be checked, and only once marked suspicious. A summary
    cannot be checked: ask for more, then check the statements behind it one by one.
  * A check opens that one item's sealed verdict from the package (see case-format.md), never the truth.
  * `unrelated` is a wrong call and costs a strike. `connected` and `uncertain` cost nothing.
  * Asking about the same item again repeats the answer for free.
  * After three strikes, no new checks.
* **Results:** a result carries only the verdict, a reason (`web`, `outside`, `where_when`, `untraced`) and
  the strike count. It never says who did it, whether anything is true, or what the answer is.

### How relevance is decided (`mystery/cases/relevance.py`)

* **The incident's causal web:**
  * the reveal's chain: the act, the events recorded as its causes (the pressures behind it), the related
    events, the consequences, and the discovery;
  * the responsible person's trip to the scene and away from it.

  Money provenance in the simulation links spending stolen money to the theft. When cash taken from a hidden
  stash is spent, the spending event records the withdrawal as a cause.
* **Event information** is judged by the event it stems from: connected if that event is in the web,
  unrelated if not. This covers debts, loans, refusals, payments, purchases, arguments, assaults, damage,
  injuries, noises, suspicions, traces and record lines.
  * Hearsay is traced back to the original perception, or to the fact the town always knew.
  * A misremembered or misidentified sighting is judged by what was really perceived.
  * A lie is judged by what it covers. For example, the deer story is about the vehicle's damage.
* **Where-and-when information** (presence, sightings, drunkenness, people's own accounts of where they were)
  is judged by place and time only. It is uncertain if it touches the web's footprint (the same place, within
  45 minutes), and unrelated otherwise.

The tests check two guarantees on every bundled case:
* Verdicts never depend on whether a statement is true: statements about the same event always get the same
  verdict, and a culprit's false account is judged like any other.
* Where-and-when verdicts can be re-derived from the claimed place and time alone.

## Hints: `hint()`

Hints are bought in order. The tiers are Nudge, Lead and Strong hint, and each has a cost in credits (the
case grants `hint_credits`). When none are left: *"There are no more hints for this case."* When the next one
is unaffordable: *"The next hint costs N credits; you have M."* Spent credits are recorded in `hint_spend`.

## Timeline: `timeline()`

* `entries` lists the timed entries ordered by `(time, id)`, each with the ids of the entries it conflicts with.
* `facts` collects every `fact` of every statement entry, tagged with its entry.
* **Conflicts** are pairs of entries that put the same person in different places at once. The margin `M` is
  20 minutes, because witness times are only ever approximate. Same-place claims, and claims within one
  entry, never conflict.
  * A *moment* conflicts with a *stay* elsewhere if `stay.from + M < moment < stay.to - M`.
  * Two stays conflict if they overlap by more than `2M`.
  * Two moments conflict only at the same minute.
  * Pairs are ordered by entry (prefix letter, then number), then by person.

The game flags conflicts in the notebook and the timeline. They catch lies (an alibi against a sighting) and
honest mistakes (a misremembered time) alike, and the player has to decide which is which.

## Concluding

* **`submit(mechanism, responsible, motive, cites, summary)`:**
  * The mechanism and motive must be among the case's `theory_options`.
  * `responsible` is a resident id, or null for no one.
  * Cites are notebook ids, or open record lines (cited on the fly).
  * The case is then concluded, and can be concluded only once.
* **`give_up()`:** concludes without a theory.
* **`reveal()`:** while the case is open, the result is `{"sealed": true, "model": null}` and the truth is not
  touched. Once the case is concluded, the truth is opened (for the first time), scored, the case is marked
  revealed, and every later action returns `{"error": "closed"}`.

### Scoring

| Theory | Points |
|---|---|
| None (gave up) | 0 |
| "Cannot be determined" | 50 if the case's evidence really was thin (`ambiguous`/`unsolvable`), else 15 |
| Otherwise | explanation 40 + responsibility 30 + motive 10 (for no-one cases, the motive must be `none` or `unknown`) |

Then **evidence cited** adds 5 per good citation, capped at 20, and subtracts 3 per citation of a mistaken or
lying statement. A good citation is one of:
* an accurate statement that supports the truth;
* the responsible person's own lie;
* a trace or record created by the incident's causal chain (or a ledger error, drink, repair or treatment
  record).

**Hints** subtract 5 per credit spent. The total is clamped to 0–100. Notes are added for a wrong person and
for leaning on bad statements.

### The reveal model

* `narrative`.
* `answer` and the player's `theory`, as labels.
* `score`: total, the ordered parts, and the notes.
* `timeline`: the causal chain plus the responsible person's movements, by `(time, id)`, without meals.
* `annotations`: each notebook entry that bears on the case, checked:
  * *LIE — why*, with what really happened;
  * *MISTAKEN — why*;
  * *true as far as it goes*;
  * *true*;
  * *left by: …* (traces);
  * *records: …* (record lines).
* `plain_true`: the count of true but irrelevant statements.
* `missed`: evidence channels the player never touched.
* `assessment`: the case's suitability verdict.
