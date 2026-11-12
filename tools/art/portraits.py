"""Portrait templates: one recognisable face per character, two ages, eight expressions.

Every drawing is a 256x256 SVG with a transparent background: head, hair and neck. Clothing is a separate
layer per occupation (clothes.py) drawn over the neck, so the same face can be a grocer in one town and a
mechanic in another. All faces share one geometry (eyes at y=112, mouth at y=150), which keeps the cast
consistent and the expressions comparable.
"""

from __future__ import annotations

EXPRESSIONS = ["neutral", "happy", "content", "tired", "worried", "uneasy", "guarded", "irritated"]
AGES = ["younger", "older"]
CX = 128

# name: skin, hair style, hair colour, face (cheek half-width, jaw half-width, chin), eye colour, nose, extras
CAST = {
    "agnes": dict(skin="#e8b896", hair="bun", hc="#8a3b1f", face=(47, 34, "round"), eye="#4a6b3a", nose="small",
                  extras=["glasses_round", "pearls"]),
    "anton": dict(skin="#f0c8a8", hair="crop", hc="#4a3324", face=(51, 42, "square"), eye="#3b4a5c", nose="broad",
                  extras=["stubble"]),
    "arvid": dict(skin="#f2cfb0", hair="side_part", hc="#d6b46a", face=(45, 32, "pointed"), eye="#5a7fa0",
                  nose="long", extras=["freckles"]),
    "bruno": dict(skin="#c99a70", hair="curly", hc="#24201c", face=(52, 44, "round"), eye="#3a2a1e", nose="broad",
                  extras=["beard"]),
    "clara": dict(skin="#efc3a0", hair="long", hc="#b0532a", face=(46, 33, "round"), eye="#4f7a4a", nose="small",
                  extras=["freckles"]),
    "daniel": dict(skin="#8a5a3a", hair="crop", hc="#1b1614", face=(50, 41, "square"), eye="#2a1c14",
                   nose="broad", extras=["moustache"]),
    "elias": dict(skin="#d9a57c", hair="wavy", hc="#5a3b23", face=(44, 33, "pointed"), eye="#4a3426", nose="long",
                  extras=["glasses_square"]),
    "emil": dict(skin="#f3d0b5", hair="flatcap", hc="#6b4a2e", face=(48, 38, "round"), eye="#506a80", nose="button",
                 extras=["stubble"]),
    "felix": dict(skin="#ecc29f", hair="side_part", hc="#3a2a20", face=(45, 36, "square"), eye="#3d5a4a",
                  nose="long", extras=["moustache"]),
    "greta": dict(skin="#e3b08a", hair="braids", hc="#caa45a", face=(48, 35, "round"), eye="#5a7fa0", nose="button",
                  extras=["blush"]),
    "hedda": dict(skin="#f2cdb3", hair="bob", hc="#1f1b1a", face=(45, 31, "pointed"), eye="#3a2a1e", nose="small",
                  extras=["mole"]),
    "henrik": dict(skin="#e6a98a", hair="receding", hc="#a8562b", face=(52, 42, "round"), eye="#4f7a4a",
                   nose="button", extras=["beard"]),
    "ida": dict(skin="#6e452c", hair="curly", hc="#2a1d16", face=(47, 34, "round"), eye="#2a1c14", nose="broad",
                extras=["hoops"]),
    "jonas": dict(skin="#d29a73", hair="crop", hc="#5a3b23", face=(49, 40, "square"), eye="#4a3426", nose="long",
                  extras=["scar"]),
    "lena": dict(skin="#efc6a5", hair="ponytail", hc="#6b4425", face=(46, 33, "round"), eye="#4a6b3a",
                 nose="small", extras=["glasses_round", "freckles"]),
    "margaret": dict(skin="#f1cdb6", hair="bun", hc="#8a6a4a", face=(45, 33, "pointed"), eye="#5a7fa0",
                     nose="long", extras=["pearls"]),
    "marta": dict(skin="#cc9f74", hair="long_wavy", hc="#231c19", face=(48, 35, "round"), eye="#3a2a1e",
                  nose="small", extras=["hoops"]),
    "nora": dict(skin="#f0c7a6", hair="bob_fringe", hc="#d8bb7a", face=(46, 33, "round"), eye="#5a7fa0",
                 nose="button", extras=["freckles", "blush"]),
    "oskar": dict(skin="#e9be9a", hair="receding", hc="#3b2d24", face=(51, 43, "square"), eye="#3b4a5c",
                  nose="broad", extras=["big_moustache"]),
    "ruth": dict(skin="#5a3826", hair="headscarf", hc="#2a6b55", face=(46, 34, "round"), eye="#2a1c14",
                 nose="broad", extras=["hoops"]),
    "selma": dict(skin="#e4b28e", hair="wavy", hc="#7a3b22", face=(45, 32, "pointed"), eye="#4f7a4a", nose="small",
                  extras=["glasses_square"]),
    "tomas": dict(skin="#cf9a72", hair="side_part", hc="#1e1a18", face=(46, 35, "pointed"), eye="#2a1c14",
                  nose="long", extras=["goatee"]),
    "vera": dict(skin="#f4d3bd", hair="long", hc="#c9b48e", face=(44, 31, "pointed"), eye="#6f8fa8", nose="small",
                 extras=[]),
    "viktor": dict(skin="#e7b996", hair="flatcap", hc="#3b2a1f", face=(52, 43, "square"), eye="#3b4a5c",
                   nose="broad", extras=["beard"]),
}


# ------------------------------------------------------------------ colour helpers
def _rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def _hex(c) -> str:
    return "#%02x%02x%02x" % tuple(max(0, min(255, int(round(v)))) for v in c)


def mix(a: str, b: str, t: float) -> str:
    x, y = _rgb(a), _rgb(b)
    return _hex([x[i] + (y[i] - x[i]) * t for i in range(3)])


def shade(c: str, t: float) -> str:
    return mix(c, "#000000", t) if t > 0 else mix(c, "#ffffff", -t)


# ------------------------------------------------------------------ expressions
# brows: (inner dy, outer dy, arch); eyes: (upper lid 0..1 closed, lower lid 0..1 raised, look dx, size);
# mouth: a name drawn by _mouth
FACE = {
    "neutral":   dict(brow=(0, 0, -2), eye=(0.08, 0.0, 0, 1.0), mouth="neutral"),
    "happy":     dict(brow=(-3, -2, -3), eye=(0.10, 0.45, 0, 1.0), mouth="grin"),
    "content":   dict(brow=(-1, 0, -2), eye=(0.18, 0.15, 0, 1.0), mouth="smile"),
    "tired":     dict(brow=(-1, 4, 0), eye=(0.50, 0.0, 0, 0.95), mouth="flat_down", bags=True),
    "worried":   dict(brow=(-7, 2, 1), eye=(0.0, 0.0, 0, 1.08), mouth="wobble"),
    "uneasy":    dict(brow=(-4, 1, 0), eye=(0.12, 0.0, 3.5, 1.0), mouth="tight_side", asym=3),
    "guarded":   dict(brow=(3, 1, -1), eye=(0.38, 0.08, -1.5, 0.95), mouth="pressed"),
    "irritated": dict(brow=(7, -2, 0), eye=(0.32, 0.1, 0, 0.95), mouth="frown"),
}


def _face_path(hw: float, jw: float, chin: str) -> str:
    cw = {"round": 17, "square": 25, "pointed": 9}[chin]
    cy = {"round": 182, "square": 180, "pointed": 186}[chin]
    return (f"M {CX - hw} 100 C {CX - hw} 58 {CX - hw * 0.62} 50 {CX} 50 "
            f"C {CX + hw * 0.62} 50 {CX + hw} 58 {CX + hw} 100 "
            f"C {CX + hw} 136 {CX + jw} 160 {CX + cw} 174 "
            f"Q {CX} {cy} {CX - cw} 174 "
            f"C {CX - jw} 160 {CX - hw} 136 {CX - hw} 100 Z")


def _hair_back(style: str, hc: str, hw: float) -> str:
    d = shade(hc, 0.18)
    if style in ("long", "long_wavy"):
        wave = 6 if style == "long_wavy" else 0
        return (f'<path d="M {CX - hw - 10} 96 C {CX - hw - 16} 150 {CX - hw - 24 - wave} 200 {CX - hw - 18} 250 '
                f'L {CX + hw + 18} 250 C {CX + hw + 24 + wave} 200 {CX + hw + 16} 150 {CX + hw + 10} 96 '
                f'C {CX + hw} 40 {CX - hw} 40 {CX - hw - 10} 96 Z" fill="{d}"/>')
    if style in ("bob", "bob_fringe"):
        return (f'<path d="M {CX - hw - 12} 100 C {CX - hw - 16} 140 {CX - hw - 12} 168 {CX - hw + 4} 176 '
                f'L {CX + hw - 4} 176 C {CX + hw + 12} 168 {CX + hw + 16} 140 {CX + hw + 12} 100 '
                f'C {CX + hw + 6} 42 {CX - hw - 6} 42 {CX - hw - 12} 100 Z" fill="{d}"/>')
    if style == "wavy":
        return (f'<path d="M {CX - hw - 10} 98 C {CX - hw - 18} 128 {CX - hw - 6} 140 {CX - hw - 14} 166 '
                f'C {CX - hw} 176 {CX - hw + 10} 168 {CX - hw + 6} 150 L {CX + hw - 6} 150 '
                f'C {CX + hw - 10} 168 {CX + hw} 176 {CX + hw + 14} 166 C {CX + hw + 6} 140 {CX + hw + 18} 128 '
                f'{CX + hw + 10} 98 C {CX + hw + 4} 42 {CX - hw - 4} 42 {CX - hw - 10} 98 Z" fill="{d}"/>')
    if style == "curly":
        blobs = "".join(f'<circle cx="{CX + x}" cy="{y}" r="{r}" fill="{d}"/>' for x, y, r in [
            (-hw - 6, 90, 20), (hw + 6, 90, 20), (-hw - 2, 120, 18), (hw + 2, 120, 18), (-hw + 8, 62, 22),
            (hw - 8, 62, 22), (0, 50, 26), (-24, 48, 22), (24, 48, 22), (-hw - 4, 146, 13), (hw + 4, 146, 13)])
        return blobs
    if style == "ponytail":
        return (f'<path d="M {CX + hw - 6} 84 C {CX + hw + 30} 96 {CX + hw + 34} 150 {CX + hw + 18} 196 '
                f'C {CX + hw + 8} 200 {CX + hw + 4} 160 {CX + hw - 2} 120 Z" fill="{d}"/>'
                f'<ellipse cx="{CX}" cy="82" rx="{hw + 6}" ry="40" fill="{d}"/>')
    if style == "braids":
        out = f'<ellipse cx="{CX}" cy="84" rx="{hw + 6}" ry="42" fill="{d}"/>'
        for side in (-1, 1):
            x = CX + side * (hw + 4)
            for i in range(6):
                out += f'<ellipse cx="{x + side * 2}" cy="{128 + i * 17}" rx="9" ry="10" fill="{d}" stroke="{shade(hc, 0.35)}" stroke-width="1.2"/>'
        return out
    if style in ("crop", "side_part", "receding", "flatcap"):
        return f'<path d="M {CX - hw - 2} 112 C {CX - hw - 6} 60 {CX + hw + 6} 60 {CX + hw + 2} 112 Z" fill="{d}"/>'
    if style == "bun":
        return (f'<ellipse cx="{CX}" cy="82" rx="{hw + 4}" ry="40" fill="{d}"/>'
                f'<circle cx="{CX + 8}" cy="40" r="22" fill="{d}"/>'
                f'<path d="M {CX - 10} 34 C {CX + 4} 26 {CX + 20} 30 {CX + 26} 44" stroke="{shade(hc, 0.4)}" '
                f'stroke-width="2" fill="none" opacity="0.6"/>')
    if style == "headscarf":
        return (f'<path d="M {CX - hw - 14} 120 C {CX - hw - 18} 50 {CX + hw + 18} 50 {CX + hw + 14} 120 '
                f'C {CX + hw + 18} 160 {CX + hw + 8} 190 {CX + hw - 6} 200 L {CX - hw + 6} 200 '
                f'C {CX - hw - 8} 190 {CX - hw - 18} 160 {CX - hw - 14} 120 Z" fill="{shade(hc, 0.12)}"/>')
    return ""


def _hair_front(style: str, hc: str, hw: float) -> str:
    hi = shade(hc, -0.22)
    d2 = shade(hc, 0.3)
    if style == "crop":
        return (f'<path d="M {CX - hw - 1} 92 C {CX - hw - 4} 50 {CX - 20} 38 {CX + 4} 40 C {CX + 36} 40 '
                f'{CX + hw + 6} 54 {CX + hw + 1} 92 C {CX + hw - 6} 74 {CX + 20} 66 {CX + 2} 70 '
                f'C {CX - 18} 66 {CX - hw + 6} 74 {CX - hw - 1} 92 Z" fill="{hc}"/>'
                f'<path d="M {CX - 16} 50 C {CX - 4} 44 {CX + 14} 44 {CX + 26} 50" stroke="{hi}" stroke-width="3" '
                f'fill="none" opacity="0.5" stroke-linecap="round"/>')
    if style == "side_part":
        return (f'<path d="M {CX - hw - 1} 100 C {CX - hw - 6} 56 {CX - 24} 36 {CX + 8} 38 C {CX + 40} 40 '
                f'{CX + hw + 6} 56 {CX + hw + 1} 96 C {CX + hw - 6} 80 {CX + 30} 66 {CX - 2} 70 '
                f'C {CX - 18} 72 {CX - 26} 66 {CX - 26} 60 C {CX - 30} 74 {CX - hw + 4} 80 {CX - hw - 1} 100 Z" '
                f'fill="{hc}"/><path d="M {CX - 26} 60 C {CX - 10} 48 {CX + 20} 46 {CX + 40} 58" stroke="{hi}" '
                f'stroke-width="3" fill="none" opacity="0.55" stroke-linecap="round"/>'
                f'<path d="M {CX - 26} 60 L {CX - 22} 44" stroke="{d2}" stroke-width="2" opacity="0.6"/>')
    if style in ("long", "long_wavy"):
        return (f'<path d="M {CX - hw - 4} 140 C {CX - hw - 6} 70 {CX - 20} 40 {CX} 42 C {CX + 20} 40 '
                f'{CX + hw + 6} 70 {CX + hw + 4} 140 C {CX + hw - 4} 110 {CX + hw - 8} 84 {CX + 6} 62 '
                f'L {CX} 56 L {CX - 6} 62 C {CX - hw + 8} 84 {CX - hw + 4} 110 {CX - hw - 4} 140 Z" fill="{hc}"/>'
                f'<path d="M {CX - 30} 52 C {CX - 40} 70 {CX - hw} 96 {CX - hw - 2} 130" stroke="{hi}" '
                f'stroke-width="2.5" fill="none" opacity="0.45"/>')
    if style == "wavy":
        return (f'<path d="M {CX - hw - 4} 118 C {CX - hw - 10} 60 {CX - 18} 38 {CX + 6} 40 C {CX + 36} 40 '
                f'{CX + hw + 10} 60 {CX + hw + 4} 118 C {CX + hw - 2} 96 {CX + hw - 10} 76 {CX + 18} 66 '
                f'C {CX + 6} 74 {CX - 10} 64 {CX - 22} 72 C {CX - hw + 4} 80 {CX - hw + 2} 98 {CX - hw - 4} 118 Z" '
                f'fill="{hc}"/><path d="M {CX - 30} 56 C {CX - 18} 48 {CX} 50 {CX + 10} 56" stroke="{hi}" '
                f'stroke-width="2.5" fill="none" opacity="0.5"/>')
    if style in ("bob", "bob_fringe"):
        fringe = 84 if style == "bob_fringe" else 72
        return (f'<path d="M {CX - hw - 6} 130 C {CX - hw - 10} 60 {CX - 20} 38 {CX} 40 C {CX + 20} 38 '
                f'{CX + hw + 10} 60 {CX + hw + 6} 130 C {CX + hw} 110 {CX + hw - 2} 92 {CX + hw - 6} {fringe} '
                f'L {CX - hw + 6} {fringe} C {CX - hw + 2} 92 {CX - hw} 110 {CX - hw - 6} 130 Z" fill="{hc}"/>'
                f'<path d="M {CX - 24} 50 C {CX - 8} 44 {CX + 12} 44 {CX + 28} 52" stroke="{hi}" stroke-width="3" '
                f'fill="none" opacity="0.5"/>')
    if style == "curly":
        blobs = "".join(f'<circle cx="{CX + x}" cy="{y}" r="{r}" fill="{hc}"/>' for x, y, r in [
            (-hw + 4, 74, 14), (-hw + 18, 62, 15), (-14, 56, 16), (6, 54, 16), (24, 58, 15), (hw - 14, 64, 15),
            (hw - 2, 78, 13), (-hw - 2, 92, 11), (hw + 2, 92, 11)])
        hl = "".join(f'<circle cx="{CX + x}" cy="{y}" r="4" fill="{hi}" opacity="0.35"/>' for x, y in [
            (-hw + 16, 58), (-12, 50), (8, 48), (26, 52), (hw - 14, 58)])
        return blobs + hl
    if style == "receding":
        return (f'<path d="M {CX - hw - 2} 104 C {CX - hw - 4} 84 {CX - hw + 2} 74 {CX - hw + 10} 70 '
                f'C {CX - hw + 8} 82 {CX - hw + 4} 92 {CX - hw - 2} 104 Z" fill="{hc}"/>'
                f'<path d="M {CX + hw + 2} 104 C {CX + hw + 4} 84 {CX + hw - 2} 74 {CX + hw - 10} 70 '
                f'C {CX + hw - 8} 82 {CX + hw - 4} 92 {CX + hw + 2} 104 Z" fill="{hc}"/>'
                f'<ellipse cx="{CX - 12}" cy="60" rx="14" ry="6" fill="#ffffff" opacity="0.18"/>')
    if style == "ponytail":
        return (f'<path d="M {CX - hw - 2} 100 C {CX - hw - 6} 54 {CX - 20} 38 {CX} 40 C {CX + 24} 38 '
                f'{CX + hw + 8} 54 {CX + hw + 2} 98 C {CX + hw - 8} 72 {CX + 20} 60 {CX} 62 '
                f'C {CX - 22} 60 {CX - hw + 6} 74 {CX - hw - 2} 100 Z" fill="{hc}"/>'
                f'<path d="M {CX - 30} 54 C {CX - 10} 44 {CX + 16} 44 {CX + 36} 56" stroke="{hi}" stroke-width="2.5" '
                f'fill="none" opacity="0.5"/>')
    if style == "braids":
        return (f'<path d="M {CX - hw - 2} 104 C {CX - hw - 6} 54 {CX - 20} 38 {CX} 40 C {CX + 20} 38 '
                f'{CX + hw + 6} 54 {CX + hw + 2} 104 C {CX + hw - 6} 76 {CX + 18} 62 {CX} 58 '
                f'C {CX - 18} 62 {CX - hw + 6} 76 {CX - hw - 2} 104 Z" fill="{hc}"/>'
                f'<path d="M {CX} 42 L {CX} 58" stroke="{d2}" stroke-width="2"/>')
    if style == "bun":
        return (f'<path d="M {CX - hw - 1} 100 C {CX - hw - 4} 54 {CX - 20} 40 {CX} 42 C {CX + 20} 40 '
                f'{CX + hw + 4} 54 {CX + hw + 1} 100 C {CX + hw - 8} 74 {CX + 18} 60 {CX} 58 '
                f'C {CX - 18} 60 {CX - hw + 8} 74 {CX - hw - 1} 100 Z" fill="{hc}"/>'
                f'<path d="M {CX - 34} 70 C {CX - 22} 54 {CX - 6} 50 {CX} 46 M {CX + 34} 70 C {CX + 22} 54 '
                f'{CX + 6} 50 {CX} 46" stroke="{hi}" stroke-width="2" fill="none" opacity="0.5"/>')
    if style == "flatcap":
        cap = "#6d6455"
        return (f'<path d="M {CX - hw - 2} 100 C {CX - hw - 4} 84 {CX - hw} 76 {CX - hw + 6} 74 L {CX - hw + 6} 100 Z" '
                f'fill="{hc}"/><path d="M {CX + hw + 2} 100 C {CX + hw + 4} 84 {CX + hw} 76 {CX + hw - 6} 74 '
                f'L {CX + hw - 6} 100 Z" fill="{hc}"/>'
                f'<path d="M {CX - hw - 8} 76 C {CX - hw - 6} 40 {CX - 10} 26 {CX + 16} 30 C {CX + 44} 34 '
                f'{CX + hw + 10} 50 {CX + hw + 8} 74 Z" fill="{cap}"/>'
                f'<path d="M {CX - hw - 10} 76 C {CX - 20} 62 {CX + 30} 62 {CX + hw + 20} 80 C {CX + 30} 90 '
                f'{CX - 20} 86 {CX - hw - 10} 76 Z" fill="{shade(cap, 0.25)}"/>'
                f'<path d="M {CX - 30} 44 L {CX + 30} 40 M {CX - 34} 54 L {CX + 36} 50" stroke="{shade(cap, -0.15)}" '
                f'stroke-width="1.5" opacity="0.6"/>')
    if style == "headscarf":
        sc = hc
        return (f'<path d="M {CX - hw - 10} 108 C {CX - hw - 14} 44 {CX + hw + 14} 44 {CX + hw + 10} 108 '
                f'C {CX + hw} 86 {CX + hw - 6} 74 {CX + 10} 70 C {CX - 10} 68 {CX - hw + 4} 78 {CX - hw - 10} 108 Z" '
                f'fill="{sc}"/><path d="M {CX - hw} 60 C {CX - 10} 48 {CX + 20} 48 {CX + hw} 62" stroke="{shade(sc, -0.25)}" '
                f'stroke-width="3" fill="none" opacity="0.5"/>'
                f'<circle cx="{CX + 30}" cy="64" r="3" fill="{shade(sc, -0.35)}"/><circle cx="{CX - 20}" cy="58" r="3" '
                f'fill="{shade(sc, -0.35)}"/><circle cx="{CX + 4}" cy="54" r="3" fill="{shade(sc, -0.35)}"/>')
    return ""


def _eye(x: float, side: int, e: dict, eye_col: str, skin: str, older: bool, line: str) -> str:
    lid, low, dx, size = e
    rx, ry = 9.5 * size, 5.8 * size
    y = 112
    out = [f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="#f7f2ea"/>',
           f'<circle cx="{x + dx}" cy="{y + 0.4}" r="{4.4 * size}" fill="{eye_col}"/>',
           f'<circle cx="{x + dx}" cy="{y + 0.4}" r="{2.1 * size}" fill="#15110e"/>',
           f'<circle cx="{x + dx - 1.4}" cy="{y - 1.6}" r="1.2" fill="#ffffff" opacity="0.9"/>']
    top = y - ry
    # upper lid: skin covers the eye from the top down to the lid line
    lid_y = top + 2 * ry * lid
    out.append(f'<path d="M {x - rx - 2} {y - ry - 6} L {x + rx + 2} {y - ry - 6} L {x + rx + 2} {lid_y + 1} '
               f'Q {x} {lid_y - 3 + 2 * lid} {x - rx - 2} {lid_y + 1} Z" fill="{skin}"/>')
    out.append(f'<path d="M {x - rx} {lid_y + 1} Q {x} {lid_y - 4 + 3 * lid} {x + rx} {lid_y + 1}" stroke="{line}" '
               f'stroke-width="2.2" fill="none" stroke-linecap="round"/>')
    if low > 0:
        ly = y + ry - 2 * ry * low
        out.append(f'<path d="M {x - rx - 2} {y + ry + 6} L {x + rx + 2} {y + ry + 6} L {x + rx + 2} {ly} '
                   f'Q {x} {ly - 4} {x - rx - 2} {ly} Z" fill="{skin}"/>')
        out.append(f'<path d="M {x - rx + 1} {ly + 0.5} Q {x} {ly - 4} {x + rx - 1} {ly + 0.5}" stroke="{shade(skin, 0.28)}" '
                   f'stroke-width="1.4" fill="none"/>')
    if older:
        out.append(f'<path d="M {x - rx + 2} {y + ry + 3} Q {x} {y + ry + 6} {x + rx - 2} {y + ry + 3}" '
                   f'stroke="{shade(skin, 0.25)}" stroke-width="1.2" fill="none" opacity="0.7"/>')
        cx = x + side * (rx + 4)
        out.append(f'<path d="M {cx} {y - 3} l {side * 5} -2 M {cx} {y + 1} l {side * 6} 1 M {cx} {y + 4} l {side * 5} 3" '
                   f'stroke="{shade(skin, 0.3)}" stroke-width="1" opacity="0.6"/>')
    return "".join(out)


def _brow(side: int, b: tuple, col: str, extra_dy: float = 0) -> str:
    inner_dy, outer_dy, arch = b
    xi, xo = CX + side * 9, CX + side * 33
    yi, yo = 95 + inner_dy + extra_dy, 96 + outer_dy + extra_dy
    mx = (xi + xo) / 2
    my = (yi + yo) / 2 - 4 + arch
    return (f'<path d="M {xi} {yi} Q {mx} {my} {xo} {yo}" stroke="{col}" stroke-width="5" fill="none" '
            f'stroke-linecap="round"/>')


def _mouth(kind: str, skin: str, w: float) -> str:
    lip = mix(skin, "#a8464a", 0.45)
    line = shade(lip, 0.45)
    y = 150
    if kind == "grin":
        return (f'<path d="M {CX - w - 3} {y - 3} Q {CX} {y + 18} {CX + w + 3} {y - 3} Q {CX} {y + 4} {CX - w - 3} {y - 3} Z" '
                f'fill="#5a1f22"/><path d="M {CX - w + 1} {y - 0.5} Q {CX} {y + 5} {CX + w - 1} {y - 0.5} L {CX + w - 3} {y + 3} '
                f'Q {CX} {y + 7} {CX - w + 3} {y + 3} Z" fill="#f3efe8"/>'
                f'<path d="M {CX - w - 3} {y - 3} Q {CX} {y + 18} {CX + w + 3} {y - 3}" stroke="{line}" stroke-width="1.6" fill="none"/>')
    paths = {
        "neutral": f"M {CX - w} {y} Q {CX} {y + 2.5} {CX + w} {y}",
        "smile": f"M {CX - w - 1} {y - 2} Q {CX} {y + 8} {CX + w + 1} {y - 2}",
        "flat_down": f"M {CX - w} {y + 2} Q {CX} {y - 1} {CX + w} {y + 2}",
        "wobble": f"M {CX - w} {y + 3} Q {CX - w / 2} {y - 2} {CX} {y + 1} Q {CX + w / 2} {y + 4} {CX + w} {y}",
        "tight_side": f"M {CX - w * 0.6} {y + 1} Q {CX + 2} {y - 1} {CX + w * 0.85} {y - 2}",
        "pressed": f"M {CX - w * 0.8} {y + 0.5} L {CX + w * 0.8} {y + 0.5}",
        "frown": f"M {CX - w} {y + 5} Q {CX} {y - 4} {CX + w} {y + 5}",
    }
    width = 3.2 if kind == "pressed" else 2.6
    lower = "" if kind in ("pressed", "tight_side") else \
        f'<path d="M {CX - w * 0.55} {y + 5} Q {CX} {y + 9} {CX + w * 0.55} {y + 5}" stroke="{lip}" stroke-width="3" ' \
        f'fill="none" opacity="0.55" stroke-linecap="round"/>'
    return lower + f'<path d="{paths[kind]}" stroke="{line}" stroke-width="{width}" fill="none" stroke-linecap="round"/>'


def _nose(kind: str, skin: str) -> str:
    s = shade(skin, 0.22)
    if kind == "broad":
        return (f'<path d="M {CX + 4} 114 Q {CX + 9} 128 {CX + 9} 134" stroke="{s}" stroke-width="2" fill="none"/>'
                f'<path d="M {CX - 11} 134 Q {CX - 6} 141 {CX} 139 Q {CX + 6} 141 {CX + 11} 134" stroke="{s}" '
                f'stroke-width="2.2" fill="none" stroke-linecap="round"/>')
    if kind == "long":
        return (f'<path d="M {CX + 2} 108 Q {CX + 8} 128 {CX + 6} 138" stroke="{s}" stroke-width="2" fill="none"/>'
                f'<path d="M {CX - 7} 137 Q {CX} 142 {CX + 7} 137" stroke="{s}" stroke-width="2" fill="none" '
                f'stroke-linecap="round"/>')
    if kind == "button":
        return (f'<ellipse cx="{CX}" cy="134" rx="6" ry="4" fill="{shade(skin, 0.08)}"/>'
                f'<path d="M {CX - 6} 135 Q {CX} 139 {CX + 6} 135" stroke="{s}" stroke-width="1.8" fill="none"/>')
    return (f'<path d="M {CX + 3} 116 Q {CX + 7} 128 {CX + 5} 134" stroke="{s}" stroke-width="1.8" fill="none"/>'
            f'<path d="M {CX - 6} 135 Q {CX} 139 {CX + 6} 135" stroke="{s}" stroke-width="1.8" fill="none" '
            f'stroke-linecap="round"/>')


def _extras(extras: list, skin: str, hc: str, hw: float, older: bool) -> tuple[str, str]:
    """(under the hair, over everything)"""
    under, over = [], []
    dark = shade(hc, 0.1)
    for x in extras:
        if x == "freckles":
            for (dx, dy) in [(-30, 124), (-24, 128), (-34, 130), (-20, 122), (30, 124), (24, 128), (34, 130), (20, 122)]:
                under.append(f'<circle cx="{CX + dx}" cy="{dy}" r="1.3" fill="{shade(skin, 0.3)}" opacity="0.7"/>')
        elif x == "blush":
            for side in (-1, 1):
                under.append(f'<ellipse cx="{CX + side * 30}" cy="130" rx="10" ry="6" fill="#e0707a" opacity="0.18"/>')
        elif x == "mole":
            under.append(f'<circle cx="{CX + 24}" cy="142" r="2" fill="{shade(skin, 0.5)}"/>')
        elif x == "scar":
            under.append(f'<path d="M {CX - 36} 118 L {CX - 28} 136" stroke="{shade(skin, 0.25)}" stroke-width="2" '
                         f'stroke-linecap="round"/><path d="M {CX - 35} 124 l 5 -2 M {CX - 32} 130 l 5 -2" '
                         f'stroke="{shade(skin, 0.25)}" stroke-width="1.2"/>')
        elif x == "stubble":
            under.append(f'<path d="M {CX - hw + 6} 128 C {CX - hw + 10} 160 {CX - 20} 178 {CX} 180 C {CX + 20} 178 '
                         f'{CX + hw - 10} 160 {CX + hw - 6} 128 C {CX + 20} 160 {CX - 20} 160 {CX - hw + 6} 128 Z" '
                         f'fill="{dark}" opacity="0.16"/>')
        elif x in ("beard", "goatee"):
            if x == "beard":
                over.append(f'<path d="M {CX - hw + 2} 118 C {CX - hw} 166 {CX - 22} 196 {CX} 198 C {CX + 22} 196 '
                            f'{CX + hw} 166 {CX + hw - 2} 118 C {CX + hw - 10} 150 {CX + 22} 140 {CX + 14} 146 '
                            f'Q {CX} 142 {CX - 14} 146 C {CX - 22} 140 {CX - hw + 10} 150 {CX - hw + 2} 118 Z" fill="{hc}"/>'
                            f'<path d="M {CX - 14} 158 Q {CX} 162 {CX + 14} 158" stroke="{shade(hc, 0.4)}" stroke-width="2" fill="none"/>')
            else:
                over.append(f'<path d="M {CX - 12} 162 Q {CX} 192 {CX + 12} 162 Q {CX} 168 {CX - 12} 162 Z" fill="{hc}"/>'
                            f'<path d="M {CX - 16} 144 Q {CX} 138 {CX + 16} 144 Q {CX} 142 {CX - 16} 144 Z" fill="{hc}"/>')
        elif x == "moustache":
            over.append(f'<path d="M {CX - 18} 147 Q {CX - 8} 138 {CX} 142 Q {CX + 8} 138 {CX + 18} 147 '
                        f'Q {CX} 143 {CX - 18} 147 Z" fill="{hc}"/>')
        elif x == "big_moustache":
            over.append(f'<path d="M {CX - 26} 152 Q {CX - 14} 134 {CX} 141 Q {CX + 14} 134 {CX + 26} 152 '
                        f'Q {CX + 10} 144 {CX} 146 Q {CX - 10} 144 {CX - 26} 152 Z" fill="{hc}"/>')
        elif x == "glasses_round":
            over.append(f'<g stroke="#2a2420" stroke-width="2.4" fill="#cfe3ef" fill-opacity="0.12">'
                        f'<circle cx="{CX - 21}" cy="113" r="13"/><circle cx="{CX + 21}" cy="113" r="13"/></g>'
                        f'<path d="M {CX - 8} 112 Q {CX} 108 {CX + 8} 112 M {CX - 34} 111 L {CX - hw} 106 M {CX + 34} 111 '
                        f'L {CX + hw} 106" stroke="#2a2420" stroke-width="2.2" fill="none"/>')
        elif x == "glasses_square":
            over.append(f'<g stroke="#3a2c22" stroke-width="2.6" fill="#cfe3ef" fill-opacity="0.12">'
                        f'<rect x="{CX - 35}" y="103" width="27" height="19" rx="4"/>'
                        f'<rect x="{CX + 8}" y="103" width="27" height="19" rx="4"/></g>'
                        f'<path d="M {CX - 8} 110 L {CX + 8} 110 M {CX - 35} 108 L {CX - hw} 104 M {CX + 35} 108 L {CX + hw} 104" '
                        f'stroke="#3a2c22" stroke-width="2.4" fill="none"/>')
        elif x == "pearls":
            for side in (-1, 1):
                over.append(f'<circle cx="{CX + side * (hw + 1)}" cy="128" r="3.6" fill="#f4efe4" stroke="#cbbfa8" stroke-width="1"/>')
        elif x == "hoops":
            for side in (-1, 1):
                over.append(f'<circle cx="{CX + side * (hw + 1)}" cy="134" r="6" fill="none" stroke="#d6a640" stroke-width="2.2"/>')
    return "".join(under), "".join(over)


def portrait_svg(name: str, age: str, expression: str) -> str:
    c = CAST[name]
    older = age == "older"
    skin = c["skin"]
    hc = mix(c["hc"], "#bdb8ae", 0.62) if older and c["hair"] != "headscarf" else c["hc"]
    hw, jw, chin = c["face"]
    face = FACE[expression]
    line = shade(skin, 0.6)
    brow_col = shade(hc if c["hair"] not in ("headscarf",) else "#2a1d16", 0.15)
    if older:
        brow_col = mix(brow_col, "#a8a49c", 0.4)
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">']
    parts.append(_hair_back(c["hair"], hc, hw))
    # neck and ears
    parts.append(f'<path d="M {CX - 21} 150 L {CX - 25} 256 L {CX + 25} 256 L {CX + 21} 150 Z" fill="{shade(skin, 0.14)}"/>')
    parts.append(f'<path d="M {CX - 21} 168 Q {CX} 190 {CX + 21} 168 L {CX + 21} 180 Q {CX} 200 {CX - 21} 180 Z" '
                 f'fill="{shade(skin, 0.24)}" opacity="0.5"/>')
    for side in (-1, 1):
        parts.append(f'<ellipse cx="{CX + side * hw}" cy="116" rx="8" ry="13" fill="{shade(skin, 0.06)}"/>'
                     f'<ellipse cx="{CX + side * (hw + 1)}" cy="116" rx="3.5" ry="7" fill="{shade(skin, 0.2)}" opacity="0.6"/>')
    parts.append(f'<path d="{_face_path(hw, jw, chin)}" fill="{skin}"/>')
    # soft shading on one side, and the cheeks
    parts.append(f'<path d="M {CX + hw - 2} 96 C {CX + hw} 136 {CX + jw} 158 {CX + 14} 174 C {CX + jw - 6} 150 '
                 f'{CX + hw - 12} 130 {CX + hw - 2} 96 Z" fill="{shade(skin, 0.12)}" opacity="0.55"/>')
    under, over = _extras(c["extras"], skin, hc, hw, older)
    parts.append(under)
    if older:
        parts.append(f'<path d="M {CX - 22} 80 Q {CX} 77 {CX + 22} 80 M {CX - 16} 86 Q {CX} 84 {CX + 16} 86" '
                     f'stroke="{shade(skin, 0.22)}" stroke-width="1.3" fill="none" opacity="0.8"/>')
        parts.append(f'<path d="M {CX - 13} 136 Q {CX - 22} 146 {CX - 22} 156 M {CX + 13} 136 Q {CX + 22} 146 {CX + 22} 156" '
                     f'stroke="{shade(skin, 0.24)}" stroke-width="1.5" fill="none" opacity="0.75"/>')
    if face.get("bags"):
        for side in (-1, 1):
            parts.append(f'<path d="M {CX + side * 12} 122 Q {CX + side * 21} 127 {CX + side * 30} 122" '
                         f'stroke="{shade(skin, 0.3)}" stroke-width="1.6" fill="none" opacity="0.7"/>')
    asym = face.get("asym", 0)
    for side in (-1, 1):
        parts.append(_eye(CX + side * 21, side, face["eye"], c["eye"], skin, older, line))
        parts.append(_brow(side, face["brow"], brow_col, -asym if side == 1 else 0))
    parts.append(_nose(c["nose"], skin))
    mw = 16 + (hw - 44) * 0.6
    parts.append(_mouth(face["mouth"], skin, mw))
    parts.append(over)
    parts.append(_hair_front(c["hair"], hc, hw))
    parts.append("</svg>")
    return "".join(parts)
