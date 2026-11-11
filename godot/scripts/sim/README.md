# Reserved: the in-engine simulation

This folder is reserved for porting the town simulation into Godot. It is empty on purpose.

Until the port is done, the Python laboratory (`mystery/sim`, `mystery/cases`) is the reference implementation
and the only source of cases. The game plays the `.mcase` packages it produces. The rules
(`scripts/core`) and the interface (`scripts/ui`) depend only on that package format, never on how a case was
generated. So a simulation added here only has to write the same packages.

The step-by-step plan, and the parity tests each step must pass against Python, are in
[`docs/godot-migration.md`](../../../docs/godot-migration.md#porting-the-simulation-later).

Keep the layers apart here as the Python code does:

* world state and the objective event log;
* character decisions;
* perception and memory;
* witness and evidence generation, and export.

The investigation rules must never read anything from this folder.
