# Replacing the artwork

Every picture, line of text and sound in Project Mystery has a template made for it. Templates are the
files named `template_…`. To use your own art, make a file with **the same name without `template_`**.
The game picks it up the next time it starts. No code changes, and nothing is overwritten: delete your
file and the template comes back.

## Where to put your files

Use the first of these that suits you:

1. **Next to the game:** an `art` folder beside `ProjectMystery.exe`, with the same sub-folders as here.
   Example: `ProjectMystery/art/portraits/clara/younger_worried.png`. No tools needed.
2. **The game's user folder:** `%APPDATA%\ProjectMystery\art\…` on Windows.
3. **In this project, if you use the Godot editor:** next to the template, e.g.
   `res://art/portraits/clara/younger_worried.png`. The editor imports it; re-export the game to ship it.

Pictures may be `.png`, `.jpg`, `.jpeg`, `.webp` or `.svg`, at any size: they are scaled to fit, keeping
their shape. Keep the same proportions as the template (and a transparent background where the template
has one) for the best result. If a picture is missing or can't be read, the game falls back to the
template, then to its own drawing.

## What there is

| Folder | Files | Size | Notes |
|---|---|---|---|
| `portraits/<name>/` | `template_<age>_<expression>.png` | 256×256, transparent | Head, hair and neck. `<name>` is the resident's id (their first name, lower case). `<age>`: `younger` (young adult, adult) or `older` (middle-aged, older). `<expression>`: `neutral`, `happy`, `content`, `tired`, `worried`, `uneasy`, `guarded`, `irritated`. |
| `clothes/` | `template_<occupation>.png` | 256×256, transparent | Drawn over the portrait's neck and shoulders. `mill_hand`, `mill_owner`, `grocer`, `shop_assistant`, `publican`, `barhand`, `nurse`, `mechanic`, `unemployed`, `retiree`. |
| `houses/` | `template_<family>_<condition>.png` | 320×224, transparent, ground at y=200 | One design per family name (`ash`, `brandt`, `carver`, `dunmore`, `harrow`, `holm`, `kessler`, `lind`, `morrow`, `okafor`, `pryce`, `vale`). `<condition>`: `fine`, `tidy`, `plain`, `worn`, from the household's standing in town. |
| `gardens/` | `template_neat.png`, `template_wild.png` | 320×224, transparent | Laid over a house: how houseproud the family is. |
| `props/` | `template_<occupation>.png` | 320×224, transparent | Laid over a house, bottom right: something that shows the household's work. A second trade is mirrored to the left. |
| `places/` | `template_<kind>.png`, `template_pub_<name>.png` | 320×224, transparent | `shop` (the grocery), `pub`, `mill`, `clinic`, `workshop`, `square`, `road`. Pubs by name: `pub_drovers_rest`, `pub_crooked_pike`, `pub_lantern`, `pub_grey_heron` (any other name uses `pub`). |
| `intro/` | `template_frame_1.png` … `template_frame_5.png`, `template_captions.txt` | 960×540 | The opening. Up to eight frames are shown, as many as there are. Captions: one line per frame. |
| `sounds/` | `template_intuition.wav` | 16-bit PCM WAV | The detective's intuition chime. |

**New characters.** A resident whose id has no folder here still gets a face: one of the cast, always the
same one for that id. To give them their own, add `portraits/<their id>/younger_neutral.png` (and as many
other expressions and the `older` age as you like). Missing expressions fall back to `neutral`.

**What the pictures may and may not say.** Faces react to the conversation and to people's manner, never to
guilt. Houses show what anyone walking past could see: a family's standing (their work), how houseproud
they are, their trade. Neither is evidence. Please keep it that way in your own art.

## Remaking the templates

The templates are drawn in code (`tools/art/*.py`) and rendered with the browser that comes with Playwright:

```bash
python3 tools/art/make_art.py
```

That rewrites only `template_*` files. Your own files are never touched.
