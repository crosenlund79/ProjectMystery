"""The opening vignette: five still frames (960x540) of a night in town that ends badly for someone.

Nobody in them can be recognised, and nothing in them belongs to any playable case: it sets the mood and
the job (somebody has to find out what happened), and says nothing about who did it.
"""

from __future__ import annotations

import math
import random

FW, FH = 960, 540
FRAMES = ["night", "mill", "water", "doorway", "dawn"]
CAPTIONS = {
    "night": "The town sleeps. Mostly.",
    "mill": "Someone is still awake down at the mill.",
    "water": "By the water, a lantern goes out.",
    "doorway": "Footsteps. A door. Then nothing.",
    "dawn": "By morning everyone has a story. Only one of them is the truth.",
}


def _svg(body: str) -> str:
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{FW}" height="{FH}" viewBox="0 0 {FW} {FH}">{body}</svg>'


def _sky(top: str, bottom: str, gid: str) -> str:
    return (f'<defs><linearGradient id="{gid}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{top}"/>'
            f'<stop offset="1" stop-color="{bottom}"/></linearGradient>'
            f'<radialGradient id="glow" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#f2c45a" stop-opacity="0.75"/>'
            f'<stop offset="1" stop-color="#f2c45a" stop-opacity="0"/></radialGradient>'
            f'<radialGradient id="vig" cx="0.5" cy="0.5" r="0.75"><stop offset="0.55" stop-color="#000" stop-opacity="0"/>'
            f'<stop offset="1" stop-color="#000" stop-opacity="0.75"/></radialGradient></defs>'
            f'<rect width="{FW}" height="{FH}" fill="url(#{gid})"/>')


def _stars(rng: random.Random, n: int, maxy: int) -> str:
    return "".join(f'<circle cx="{rng.uniform(0, FW):.1f}" cy="{rng.uniform(0, maxy):.1f}" r="{rng.uniform(0.6, 1.6):.1f}" '
                   f'fill="#e8e6f0" opacity="{rng.uniform(0.3, 0.9):.2f}"/>' for _ in range(n))


def _houses(rng: random.Random, base: float, col: str, lit: float, scale: float = 1.0) -> str:
    out, x = [], -20.0
    while x < FW + 20:
        w = rng.uniform(70, 130) * scale
        h = rng.uniform(60, 120) * scale
        roof = rng.uniform(26, 50) * scale
        out.append(f'<path d="M {x} {base} L {x} {base - h} L {x + w / 2} {base - h - roof} L {x + w} {base - h} L {x + w} {base} Z" fill="{col}"/>')
        if rng.random() < 0.6:
            cx = x + w * rng.uniform(0.15, 0.8)
            out.append(f'<rect x="{cx}" y="{base - h - roof * 0.7}" width="{10 * scale}" height="{roof * 0.8}" fill="{col}"/>')
        for _ in range(rng.randint(1, 3)):
            wx = x + rng.uniform(10, w - 24 * scale)
            wy = base - rng.uniform(20, h - 10) * 1.0
            on = rng.random() < lit
            out.append(f'<rect x="{wx:.1f}" y="{wy:.1f}" width="{12 * scale:.1f}" height="{14 * scale:.1f}" '
                       f'fill="{"#f2c45a" if on else "#1a1d26"}" opacity="{0.95 if on else 1}"/>')
        x += w + rng.uniform(4, 30)
    return "".join(out)


def _rain(rng: random.Random, n: int) -> str:
    return "".join(f'<path d="M {rng.uniform(0, FW):.1f} {rng.uniform(0, FH):.1f} l -6 18" stroke="#9aa8c0" '
                   f'stroke-width="1.2" opacity="{rng.uniform(0.15, 0.4):.2f}"/>' for _ in range(n))


def _vignette() -> str:
    return f'<rect width="{FW}" height="{FH}" fill="url(#vig)"/>'


def frame_svg(name: str) -> str:
    rng = random.Random(name)
    o = []
    if name == "night":
        o.append(_sky("#0b1020", "#26304a", "s1"))
        o.append(_stars(rng, 160, 300))
        o.append('<circle cx="760" cy="110" r="46" fill="#e8e2c8"/><circle cx="742" cy="98" r="46" fill="#11182a" opacity="0.18"/>')
        o.append('<circle cx="760" cy="110" r="120" fill="#e8e2c8" opacity="0.06"/>')
        o.append(_houses(random.Random("far"), 420, "#151a28", 0.15, 0.7))
        o.append(_houses(random.Random("near"), 540, "#0c0f17", 0.35, 1.25))
        o.append('<rect x="0" y="380" width="960" height="70" fill="#aab4c8" opacity="0.07"/>')
        o.append('<rect x="0" y="420" width="960" height="40" fill="#aab4c8" opacity="0.06"/>')
    elif name == "mill":
        o.append(_sky("#0a0f1c", "#1c2436", "s2"))
        o.append(_stars(rng, 60, 200))
        o.append('<path d="M 0 430 C 200 410 400 440 960 420 L 960 540 L 0 540 Z" fill="#141c2a"/>')
        o.append('<path d="M 0 470 C 300 455 600 480 960 462 L 960 540 L 0 540 Z" fill="#1d2c3e"/>')
        for i in range(14):
            o.append(f'<path d="M {40 + i * 70} {478 + (i % 3) * 6} l 40 0" stroke="#5a7a9a" stroke-width="2" opacity="0.35"/>')
        o.append('<path d="M 300 430 L 300 230 L 450 150 L 600 230 L 600 430 Z" fill="#0d121c"/>')
        o.append('<rect x="520" y="110" width="26" height="80" fill="#0d121c"/>')
        o.append('<rect x="408" y="290" width="34" height="42" fill="#f2c45a"/><circle cx="425" cy="311" r="70" fill="url(#glow)" opacity="0.6"/>')
        o.append('<rect x="408" y="310" width="34" height="2" fill="#0d121c"/><rect x="424" y="290" width="2" height="42" fill="#0d121c"/>')
        o.append('<circle cx="660" cy="400" r="70" fill="none" stroke="#0d121c" stroke-width="12"/>')
        for i in range(8):
            a = i * math.pi / 4
            o.append(f'<path d="M 660 400 L {660 + 70 * math.cos(a):.1f} {400 + 70 * math.sin(a):.1f}" stroke="#0d121c" stroke-width="7"/>')
        o.append('<path d="M 425 332 L 440 470" stroke="#f2c45a" stroke-width="20" opacity="0.06"/>')
        o.append(_rain(rng, 260))
    elif name == "water":
        o.append(_sky("#070b14", "#141c2a", "s3"))
        o.append('<circle cx="180" cy="90" r="30" fill="#d8d2b8" opacity="0.9"/>')
        o.append('<rect x="0" y="300" width="960" height="240" fill="#0e1622"/>')
        for i in range(30):
            y = 310 + i * 8
            o.append(f'<path d="M {rng.uniform(80, 280):.1f} {y} l {rng.uniform(20, 60):.1f} 0" stroke="#d8d2b8" stroke-width="2" opacity="{0.35 - i * 0.01:.2f}"/>')
        o.append('<path d="M 0 300 C 160 288 320 312 540 296 C 700 286 820 300 960 292 L 960 330 C 700 320 500 336 0 326 Z" fill="#0a0f18"/>')
        for i in range(60):  # reeds
            x = rng.uniform(560, 960)
            h = rng.uniform(40, 120)
            o.append(f'<path d="M {x:.1f} 330 q {rng.uniform(-8, 8):.1f} {-h / 2:.1f} {rng.uniform(-14, 14):.1f} {-h:.1f}" stroke="#141c18" stroke-width="3" fill="none"/>')
        # a dropped lantern on its side, still glowing faintly
        o.append('<circle cx="640" cy="318" r="80" fill="url(#glow)" opacity="0.45"/>')
        o.append('<g transform="rotate(78 640 318)"><rect x="628" y="296" width="24" height="34" rx="3" fill="#2a2216" stroke="#0a0a0a" stroke-width="3"/>'
                 '<rect x="633" y="301" width="14" height="24" fill="#f2c45a" opacity="0.8"/><path d="M 626 296 L 640 284 L 654 296" fill="#0a0a0a"/></g>')
        # a hat drifting away
        o.append('<ellipse cx="380" cy="404" rx="40" ry="8" fill="#1a1612"/><path d="M 356 404 Q 358 382 380 380 Q 402 382 404 404 Z" fill="#1f1a15"/>')
        for i in range(3):
            o.append(f'<ellipse cx="380" cy="406" rx="{56 + i * 22}" ry="{10 + i * 4}" fill="none" stroke="#8a9ab0" stroke-width="1.2" opacity="{0.25 - i * 0.07:.2f}"/>')
    elif name == "doorway":
        o.append('<rect width="960" height="540" fill="#0c0e14"/>')
        o.append('<path d="M 0 0 L 520 0 L 520 540 L 0 540 Z" fill="#1a1d26"/>')
        for r in range(0, 540, 28):
            for c in range(0, 520, 56):
                o.append(f'<rect x="{c + (14 if (r // 28) % 2 else 0)}" y="{r}" width="54" height="26" fill="#20242e" stroke="#15171e" stroke-width="2"/>')
        o.append('<path d="M 600 0 L 960 0 L 960 540 L 600 540 Z" fill="#14161d"/>')
        o.append('<rect x="660" y="120" width="160" height="420" fill="#07080b"/><path d="M 660 120 A 80 70 0 0 1 820 120" fill="#07080b"/>')
        o.append('<rect x="560" y="60" width="10" height="480" fill="#06070a"/><path d="M 540 40 L 590 40 L 582 70 L 548 70 Z" fill="#f2c45a"/>'
                 '<circle cx="565" cy="56" r="150" fill="url(#glow)" opacity="0.35"/>')
        # a long shadow on the wall: someone standing out of sight under the lamp, a hat, a coat
        o.append('<g opacity="0.85" fill="#050608"><path d="M 470 540 L 404 300 Q 398 276 380 270 L 330 262 Q 306 262 300 290 '
                 'L 352 540 Z"/><ellipse cx="352" cy="232" rx="30" ry="34"/><path d="M 300 214 L 410 204 L 404 192 L 382 192 '
                 'Q 376 168 350 170 Q 326 174 326 198 L 304 204 Z"/></g>')
        o.append('<circle cx="120" cy="120" r="54" fill="#d8d2b8" opacity="0.15"/><circle cx="120" cy="120" r="44" fill="none" stroke="#d8d2b8" stroke-width="3" opacity="0.5"/>'
                 '<path d="M 120 120 L 120 86 M 120 120 L 102 112" stroke="#d8d2b8" stroke-width="4" opacity="0.6"/>')  # quarter to midnight
        for i in range(12):
            a = i * math.pi / 6
            o.append(f'<circle cx="{120 + 38 * math.cos(a):.1f}" cy="{120 + 38 * math.sin(a):.1f}" r="2" fill="#d8d2b8" opacity="0.5"/>')
    elif name == "dawn":
        o.append(_sky("#3a3a58", "#d89a6a", "s5"))
        o.append('<circle cx="480" cy="470" r="90" fill="#f2c45a" opacity="0.5"/>')
        o.append(_houses(random.Random("dawn"), 430, "#2a2436", 0.05, 1.0))
        o.append('<rect x="0" y="430" width="960" height="110" fill="#3a3040"/>')
        o.append('<ellipse cx="480" cy="452" rx="70" ry="14" fill="#4a4050"/><rect x="474" y="390" width="12" height="60" fill="#4a4050"/>')
        crowd = random.Random("crowd")
        for i in range(14):  # people gathered, talking - none of them anyone in particular
            x = 260 + i * 34 + crowd.uniform(-8, 8)
            h = crowd.uniform(70, 96)
            o.append(f'<path d="M {x - 12} 470 L {x - 10} {470 - h + 26} Q {x} {470 - h + 16} {x + 10} {470 - h + 26} L {x + 12} 470 Z" fill="#1c1824"/>'
                     f'<circle cx="{x}" cy="{470 - h + 10}" r="10" fill="#1c1824"/>')
        o.append('<rect x="760" y="380" width="70" height="56" fill="#2a2228"/><rect x="766" y="386" width="58" height="44" fill="#d8ccb0" opacity="0.8"/>')
    o.append(_vignette())
    return _svg("".join(o))
