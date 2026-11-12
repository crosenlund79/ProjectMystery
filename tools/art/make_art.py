"""Make the game's template artwork (godot/art/**/template_*): portraits, clothing, houses, gardens, trade
props, workplaces, the opening vignette and the intuition chime.

    python3 tools/art/make_art.py            # everything
    python3 tools/art/make_art.py portraits  # one group: portraits, clothes, houses, places, intro, sound

Drawings are SVG (see portraits.py, clothes.py, buildings.py, intro.py), rendered to PNG by the browser that
ships with Playwright (render.mjs) and reduced to a palette. Only files named template_* are ever written:
artwork without the prefix is the user's and is never touched.
"""

from __future__ import annotations

import json
import math
import os
import struct
import subprocess
import sys
import tempfile
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from buildings import CONDITIONS, GARDENS, HOUSES, TRADES, garden_svg, house_svg, place_svg, prop_svg  # noqa: E402
from clothes import ROLES, clothes_svg  # noqa: E402
from intro import CAPTIONS, FRAMES, frame_svg  # noqa: E402
from portraits import AGES, CAST, EXPRESSIONS, portrait_svg  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(HERE))
ART = os.path.join(ROOT, "godot", "art")
PUBS = {"drovers_rest": "Drover's Rest", "crooked_pike": "Crooked Pike", "lantern": "Lantern", "grey_heron": "Grey Heron"}
PLACE_KINDS = ["shop", "pub", "mill", "clinic", "workshop", "square", "road"]


def jobs(group: str) -> list[dict]:
    out = []

    def add(rel: str, w: int, h: int, svg: str, colors: int = 128) -> None:
        out.append({"out": os.path.join(ART, rel), "w": w, "h": h, "svg": svg, "colors": colors})
    if group == "portraits":
        for name in CAST:
            for age in AGES:
                for e in EXPRESSIONS:
                    add(f"portraits/{name}/template_{age}_{e}.png", 256, 256, portrait_svg(name, age, e))
    elif group == "clothes":
        for r in ROLES:
            add(f"clothes/template_{r}.png", 256, 256, clothes_svg(r))
    elif group == "houses":
        for s in HOUSES:
            for c in CONDITIONS:
                add(f"houses/template_{s}_{c}.png", 320, 224, house_svg(s, c))
        for g in GARDENS:
            add(f"gardens/template_{g}.png", 320, 224, garden_svg(g))
        for t in TRADES:
            add(f"props/template_{t}.png", 320, 224, prop_svg(t))
    elif group == "places":
        for k in PLACE_KINDS:
            add(f"places/template_{k}.png", 320, 224, place_svg(k))
        for slug in PUBS:
            add(f"places/template_pub_{slug}.png", 320, 224, place_svg("pub", slug))
    elif group == "intro":
        for i, f in enumerate(FRAMES, 1):
            add(f"intro/template_frame_{i}.png", 960, 540, frame_svg(f), colors=0)
    return out


def render(group: str) -> int:
    todo = jobs(group)
    if not todo:
        return 0
    with tempfile.TemporaryDirectory() as tmp:
        manifest = os.path.join(tmp, "jobs.json")
        with open(manifest, "w", encoding="utf-8") as f:
            json.dump([{k: j[k] for k in ("out", "w", "h", "svg")} for j in todo], f)
        subprocess.run(["node", os.path.join(HERE, "render.mjs"), manifest], check=True)
    from PIL import Image
    for j in todo:
        im = Image.open(j["out"])
        if j["colors"]:
            im = im.convert("RGBA").quantize(colors=j["colors"], method=Image.Quantize.FASTOCTREE)
        else:
            im = im.convert("RGB")
        im.save(j["out"], optimize=True)
    return len(todo)


def captions() -> None:
    os.makedirs(os.path.join(ART, "intro"), exist_ok=True)
    with open(os.path.join(ART, "intro", "template_captions.txt"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(CAPTIONS[k] for k in FRAMES) + "\n")


def chime(path: str, rate: int = 22050, seconds: float = 1.1) -> None:
    """A small bell: a few inharmonic partials with a soft attack and a long decay."""
    partials = [(1046.5, 1.0, 4.2), (2093.0 * 1.003, 0.35, 6.0), (2886.0, 0.22, 7.5), (5650.0, 0.08, 11.0)]
    frames = bytearray()
    n = int(rate * seconds)
    for i in range(n):
        t = i / rate
        attack = min(1.0, t / 0.006)
        v = sum(a * math.exp(-d * t) * math.sin(2 * math.pi * f * t) for f, a, d in partials)
        frames += struct.pack("<h", int(max(-1.0, min(1.0, 0.32 * attack * v)) * 32767))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(bytes(frames))


def main(argv: list[str]) -> None:
    groups = argv or ["portraits", "clothes", "houses", "places", "intro", "sound"]
    for g in groups:
        if g == "sound":
            chime(os.path.join(ART, "sounds", "template_intuition.wav"))
            print("sound: 1 file")
            continue
        if g == "intro":
            captions()
        print(f"{g}: {render(g)} image(s)")


if __name__ == "__main__":
    main(sys.argv[1:])
