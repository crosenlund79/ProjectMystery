# Import-test cases

Ten extra cases for trying the game's case importer. They are **not** part of the game: nothing here is
bundled or registered, and the game doesn't know about them until you import them.

## Importing

1. Start Project Mystery and choose **Load Case**.
2. Choose **Import a case file…** and pick one of the `.mcase` files in this folder.
3. The case now appears under **New Case**.

Each file is a complete, standalone case, checked by the same validation the importer runs.

## The cases

The titles are the cases' own hooks. Nothing below says who did it.

| File | Title | Season | Difficulty |
|---|---|---|---|
| `35-normal-60d-r10-I3.mcase` | The Lighter Savings Tin | An ordinary season | standard |
| `22-normal-60d-r10-I3.mcase` | The Fight at The Lantern | An ordinary season | gentle |
| `20-normal-60d-r10-I1.mcase` | The Short Till at The Grocery | An ordinary season | standard |
| `16-scarcity-60d-r10-I2.mcase` | The Lighter Savings Tin | A lean season | standard |
| `24-scarcity-60d-r10-I2.mcase` | The Injuries of Agnes Dunmore | A lean season | standard |
| `30-crisis-60d-r10-I3.mcase` | The Smashed Fence | Hard times | standard |
| `16-crisis-60d-r10-I3.mcase` | The Lighter Savings Tin | Hard times | standard |
| `16-tension-60d-r10-I8.mcase` | The Fight at The Grey Heron | A troubled season | gentle |
| `17-tension-60d-r10-I7.mcase` | The Smashed Fence | A troubled season | gentle |
| `18-tension-60d-r10-I6.mcase` | The Lighter Savings Tin | A troubled season | standard, **the challenging one** |

They cover thefts, fights, hit-and-run collisions, an accident and a bookkeeping mistake, in all four
kinds of season.

**The challenging one** (`18-tension-60d-r10-I6`) has only one way to the answer, a lot of town talk
pointing at the wrong people, and someone who lies about where they were. It can be solved fairly: the
evidence is there for a careful detective.

## How they were made and checked

`python3 tools/make_import_cases.py` finds them in real simulated histories, using seeds the bundled
library doesn't use; nothing is edited. It keeps a case only if it can be worked out from evidence (a
contradiction that holds, an eyewitness, a trace, a record, or the only person with the opportunity). It
then plays each one through with the reference rules. See `VALIDATION.md`: every file validates, every
piece of evidence behind the answer can be reached, and a theory built on that evidence solves the case.
The Godot test `godot/tests/test_import.gd` imports all ten through the game's own importer and opens them.
