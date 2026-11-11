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

This is the same object the Python game uses as `investigation.json` (schema `investigation/0.1`). Everything
in it is something a player may legitimately discover: the hook, residents, places and vehicles, consent
decisions, what each resident is willing to say, reachable traces and records, the theory options, and the
hint ladder. It never contains event ids, intents, accuracy flags, causal links or the answer. The validator
rejects any of these keys anywhere in it: `intent`, `causes`, `status`, `lie`, `error`, `implicates`,
`responsible`, `event`, `belief`, `created_by`, `supports`, `accurate`, `answer`, `narrative`, `chain`,
`guilty_of`, `traits`. It also rejects any `E######` event id or `B######` belief id in its text.

| Field | Contents |
|---|---|
| `hook` | `title`, `text`, `kind`, `place`, `window` (two minute times), `window_label`, `discovered_by` |
| `residents[]` | `id`, `name`, `first`, `occupation`, `age_group`, `household`, `home`, `condition` (`alive`/`injured`/`deceased`) |
| `places[]` | `id`, `name`, `kind`, `owners[]`, `allowed`, `reply`, `traces[]` (`id`, `description`); traces are empty when not allowed |
| `vehicles[]` | `id`, `name`, `kind`, `household`, `location`, `allowed`, `reply`, `traces[]` |
| `records{book}` | `title`, `place`, `allowed`, `reply`, `entries[]` (`id`, `time`, `text`); entries are empty when not allowed |
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
