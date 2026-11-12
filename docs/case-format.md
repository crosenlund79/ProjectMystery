# Case package format (`.mcase`, version 1)

A case package is how a simulated case travels from the Python laboratory to the game. It is a single
UTF-8 JSON file. The Godot game reads it without Python, either from its bundled library or from a file the
player imports. The same file opens in the Python tools with `python -m mystery unpack-case`.

| Implementation | Where |
|---|---|
| Writer and validator (Python) | `mystery/cases/package.py` |
| Reader and validator (Godot) | `godot/scripts/core/case_format.gd` |
| Tests | `tests/test_package.py`, `godot/tests/test_case_format.gd` |

Create packages with:

```bash
python -m mystery export-godot --seed 7 --days 60 --profile normal --incident I1
```

```bash
python -m mystery build-library
```

```bash
python -m mystery validate-case path/to/*.mcase
```

## Top level

| Field | Type | Meaning |
|---|---|---|
| `format` | string | Always `"project-mystery-case"`. |
| `format_version` | int | `1`. Readers reject versions they do not know and say so. |
| `case_id` | string | `<seed>-<profile>-<days>d-r<residents>-<incident>`, e.g. `7-normal-60d-r10-I1`. |
| `generator` | object | How to regenerate the case: `tool`, `sim_version`, `config_version`, `seed`, `profile`, `days`, `residents`, `incident`, `event_log_digest`. |
| `summary` | object | Spoiler-free card for menus: `title`, `town`, `start_label`, `season`, `difficulty` (`gentle`/`standard`/`hard`/`very hard`, from the case's suitability verdict). |
| `investigation` | object | The player-safe view (below). |
| `sealed_truth` | object | The developer truth, sealed (below). |

A case regenerates exactly from `generator`, provided `sim_version` and `config_version` match. Two checks
verify this. `test_a_bundled_case_regenerates_identically_from_its_seed` does it for one case.
`build-library --check` does it for the whole bundled library in CI.

## `investigation` (player-safe)

This is the same object the Python game uses as `investigation.json` (schema `investigation/0.3`). Everything
in it is something a player may legitimately discover: the hook, residents, places and vehicles, consent
decisions, what each resident is willing to say, reachable traces and records, the theory options, and the
hint ladder. It never contains event ids, intents, accuracy flags, causal links or the answer. The validator
rejects any of these keys anywhere in it: `intent`, `causes`, `status`, `lie`, `error`, `implicates`,
`responsible`, `event`, `belief`, `created_by`, `supports`, `accurate`, `answer`, `narrative`, `chain`,
`guilty_of`, `traits`. It also rejects any `E######` event id or `B######` belief id in its text.

| Field | Contents |
|---|---|
| `hook` | `title`, `text`, `kind`, `place`, `window` (two minute times), `window_label`, `discovered_by`, `recent_from` |
| `residents[]` | `id`, `name`, `first`, `occupation`, `age_group`, `household`, `home`, `condition` (`alive`/`injured`/`deceased`), `now_at`, `role`, `demeanour` |
| `places[]` | `id`, `name`, `kind`, `owners[]`, `allowed`, `reply`, `traces[]` (`id`, `description`); traces are empty when not allowed |
| `vehicles[]` | `id`, `name`, `kind`, `household`, `location`, `allowed`, `reply`, `traces[]` |
| `records{book}` | `title`, `place`, `allowed`, `reply`, `entries[]` (`id`, `time`, `text`, `facts`); entries are empty when not allowed |
| `testimony{resident}` | `goodwill` (patience), `style` (`nervous`/`smooth`), `evasive_topics[]`, `items[]` |
| `theory_options` | `mechanisms[]` and `motives[]`, each `{id, label}` |
| `hints[]` | `{tier, cost, text}`, cheapest first; built only from evidence the player can reach |
| `hint_credits`, `start_time`, `start_label`, `town`, `player_role`, `case_id`, `schema` | |

Each testimony item has these fields:

| Field | Meaning |
|---|---|
| `key` | Opaque statement id (`K0001`); the reveal maps it to the truth audit. |
| `text` | The rendered sentence, exactly as the resident says it ("I saw…", "Ana told me…"). |
| `topics[]` | `whereabouts`, `window`, `incident`, `money`, `conflicts`, `rumors`, `vehicles`, `past`, `other` or `person:<id>`. |
| `source` | `self`, `saw`, `heard`, `told` or `inferred`. |
| `time`, `place`, `about[]` | When and where the statement is set, and who it mentions. |
| `guarded` | Only said when the player presses (loyalty or uncertainty). Withheld knowledge is not in the file at all; it only shows up as `evasive_topics`. |
| `group` | Optional `{id, name, template}`, which lets "I saw A, B and C at…" merge into one line. |
| `facts[]` | `{who, place, from, to, hedged}`: where the statement *claims* someone was, as the speaker recalls it, with lies and misremembered times included. The timeline and conflict detection use these. |
| `era` | Optional, `"earlier"`: about a time before `hook.recent_from`. Told when the player asks "and before that?" (schema 0.3). |
| `members[]` | Optional (schema 0.3): this statement stands in front of these statements of the same resident. A *summary* ("At the Drover's Rest, from about 18:00 to 22:00 on Day 23, I saw Agnes, Bruno and Clara, coming and going") stands for the everyday statements it sums up; a plain account of someone's whereabouts stands for the exact one. |
| `in` | Optional (schema 0.3): the key of the statement this one stands behind. Told when the player asks for more on a topic the front statement is told on; asked about a person in particular, it is told directly. |

`now_at` (added in schema 0.2, optional) is the place where the resident is at the frozen instant the case
begins. It is `null` for the dead. This is present state that anyone in town could see by walking around, not
anything about the past, and it is what the game's town uses to say who is where. Readers must accept packages
without it (schema 0.1); the game then assumes everyone is at home. Validators reject a `now_at` that is not a
known place.

### What anyone can see (schema 0.3, optional)

* `residents[].role` is the occupation's key (`mill_hand`, `grocer`, …). It chooses their work clothes.
* `residents[].demeanour` is how they come across: `cheerful`, `easygoing`, `brisk`, `reserved` or `gruff`.
  It comes only from sociability, stubbornness and diligence, traits that play no part in deciding to steal,
  fight or drive drunk.
* `places[].look`, for homes only: `{style, condition, garden, trades}`.
  * `style` is the family's house.
  * `condition` (`fine`, `tidy`, `plain`, `worn`) comes from the household's standing, that is the work its
    people do (public knowledge), never from this month's debts.
  * `garden` (`neat`, `wild`) comes from how diligent they are.
  * `trades` are their occupations.
* `records[].entries[].facts`: a line that names someone the book places there (a drink, a meal, a sale,
  credit, a treatment, a repair) carries `{who, place, from, to, hedged}` at the time written down. Lines
  about wages, takings or deliveries carry none.

Readers must accept packages without these fields. The game then gives everyone a stand-in face, ordinary
clothes and a tidy house.

### How people answer (schema 0.3)

The export shapes what each resident says the way people talk, without removing anything:

* **Recent first.** `hook.recent_from` is 13 hours before the start of the time in question (or of the last
  two days, if that window is longer). Statements about earlier times get `era: "earlier"`. Current states
  (debts still owed, grudges) and the case's own topics (`incident`, `past`) are not limited this way.
* **Everyday matters in summary.** Each summary is a statement with its own key and its own entry in the
  notebook. Its `facts` are its members' facts, so the timeline loses nothing, and it names everyone its members
  name. Summaries cover:
  * people seen at a place in one session, including who was drunk and anyone recognised in daylight passing
    through;
  * debts and repayments between other people, by creditor;
  * refusals, by who was asking;
  * who the town is pointing at over a matter;
  * the speaker's own debtors, the people who came to them for money, and the people who turned them down.

  Guarded statements, lies, sightings in the dark or of someone the speaker could not make out, vehicles,
  anyone unsteady on their feet, housemates' comings and goings and the speaker's own account are never
  summed up. A summary that concerns one person in particular (a creditor, someone asking for money) is also
  told when asked about that person.
* **Plain and exact accounts.** Asked where they were, people say where they spent their time, from when;
  asked to be exact, every move, with times. Both are statements with verdicts, and a lie is told both ways.

In the truth, a summary's audit has `summary: true`, its `members`, and a status that is `mistaken` when any
member is (with `error` "partly wrong: …"). Summaries have no relevance verdict, so Hobby Detective checks the
statements behind them one by one. Suitability channels and the reveal count a heard summary as having found
its members.

All times are minutes since Day 1 00:00. JSON numbers are integers; readers that parse numbers as floats
(Godot does) convert them back to integers.

## `sealed_truth`

```json
{"scheme": "sha256-ctr-xor/1", "length": 101234, "plain_sha256": "…", "data_sha256": "…", "data": "<base64>"}
```

* `plaintext` is the canonical JSON of the truth (`json.dumps(sort_keys=True, separators=(",", ":"),
  ensure_ascii=True)`): the incident, answer, narrative, causal chain, the responsible person's movements,
  private states, the audit of every statement (accurate, mistaken and why, or a lie and why), evidence and
  record provenance, and the suitability report.
* Keystream block `i` is `SHA-256("project-mystery case seal v1|<case_id>|<i>")`, with the blocks
  concatenated. The data is `base64(plaintext XOR keystream)`.
* `data_sha256` is the SHA-256 of the base64 text. It lets the validator detect corruption without opening
  the seal. `plain_sha256` and `length` verify the opened plaintext.

**This is a spoiler guard, not security.** The salt is public, so anyone can open the seal with the
documented tools. It exists so that menus, logs, saves and casual file browsing never show the truth, and so
that edited or damaged files are detected. In the game, only `godot/scripts/core/verdict.gd` opens it, and
only after the player has submitted a theory or given up. A counter (`Verdict.unseal_count`) lets the tests
prove this.

## `relevance` (optional, per-item seals)

```json
{"scheme": "sha256-xor-item/1", "items": {"K0001": "<base64>", "T-EV0007": "<base64>", "R-L0042": "<base64>"}}
```

There is one entry per statement key, trace id and record line id. Each value is
`"<verdict>|<reason>"`, space-padded to 24 bytes and XORed with the first 24 bytes of
`SHA-256("project-mystery relevance v1|<case_id>|<item id>")`, then base64-encoded. Every value has the same
length, so a verdict's length does not give it away. Hobby Detective checks open exactly one item at a time and
never the truth.

The values come from `mystery/cases/relevance.py`:

| Value | Meaning |
|---|---|
| `connected|web` | It stems from an event in the incident's causal web. |
| `unrelated|outside` | It stems from an event outside the web, or it is where-and-when information that touches no part of it. |
| `uncertain|where_when` | It is where-and-when information that puts someone where and when part of the incident happened. |
| `uncertain|untraced` | It is hearsay that cannot be traced back to anything anyone perceived. |

The same verdicts, with their source events, are in the sealed truth as `relevance`, together with
`relevance_web` (the event ids) and `relevance_footprint` (`[place, minute]` pairs). The relevance block is
optional: packages without it stay readable, and the game then offers no checks. Validators reject a block
whose items do not open to one of the four values.

## Library index (`godot/cases/index.json`)

```json
{"format": "project-mystery-library", "format_version": 1, "missing": [],
 "cases": [{"file": "…mcase", "case_id": "…", "title": "…", "town": "…", "start_label": "…",
            "season": "…", "difficulty": "…", "sha256": "<sha256 of the file>"}]}
```

The game refuses to open a bundled case whose bytes no longer match `sha256`. Case files, the index and the
parity fixtures are therefore marked `-text` in `.gitattributes`, so line endings are never rewritten.

## Compatibility rules

* Adding optional fields keeps `format_version` at 1. Readers ignore unknown fields.
* Removing or renaming a field, or changing its meaning, needs `format_version` 2. Readers must then reject
  version 1 files explicitly or keep reading them.
* Any change to the simulation or export that changes generated cases needs a `CONFIG_VERSION` or
  `SIM_VERSION` bump, and `python -m mystery build-library --parity godot/tests/parity` to regenerate the
  library and parity fixtures.
