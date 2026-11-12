"""Building templates: twelve family houses (four states of repair each), garden and trade overlays, and the
town's workplaces. 320x224 drawings on a transparent background, ground line at y=200.

A house's condition comes from the household's standing in town (the work its people do), its garden from
how houseproud they are, and the props by the door from their trades - all things anyone walking past could
see. None of it says anything about who is in trouble.
"""

from __future__ import annotations

from portraits import mix, shade

W, H, G = 320, 224, 200
CONDITIONS = ["fine", "tidy", "plain", "worn"]
GARDENS = ["neat", "wild"]
TRADES = ["mill_hand", "mill_owner", "grocer", "shop_assistant", "publican", "barhand", "nurse", "mechanic",
          "unemployed", "retiree"]

# style: (x, width, wall height, wall colour, material, roof type, roof colour, door colour, windows, feature)
HOUSES = {
    "ash":     dict(x=104, w=112, h=112, wall="#9a5440", mat="brick", roof="gable", rc="#4a3c38", door="#2f4a3a",
                    win=[(118, 108), (178, 108), (118, 152)], feature="chimney_tall"),
    "brandt":  dict(x=56, w=208, h=68, wall="#e6dfcf", mat="render", roof="gable", rc="#9a3a2a", door="#7a3a24",
                    win=[(78, 146), (214, 146)], feature="porch"),
    "carver":  dict(x=84, w=152, h=72, wall="#9a7a54", mat="planks", roof="gable", rc="#5a4636", door="#3f6b4a",
                    win=[(102, 146), (190, 146)], feature="carved_gable"),
    "dunmore": dict(x=80, w=160, h=70, wall="#a39c90", mat="stone", roof="gable", rc="#4f5a63", door="#5a3a28",
                    win=[(100, 148), (192, 148)], feature="round_window"),
    "harrow":  dict(x=64, w=192, h=74, wall="#c7b8a0", mat="render", roof="hip", rc="#3f4a52", door="#4a3a5a",
                    win=[(84, 144), (126, 144), (206, 144)], feature="dormer"),
    "holm":    dict(x=72, w=176, h=76, wall="#6f8ca6", mat="clapboard", roof="gable", rc="#3a3a42", door="#e8dcc0",
                    win=[(92, 142), (198, 142)], feature="veranda"),
    "kessler": dict(x=88, w=144, h=96, wall="#efe8da", mat="timber", roof="steep", rc="#6b3f3a", door="#5a3a28",
                    win=[(106, 116), (184, 116), (106, 158)], feature="half_timber"),
    "lind":    dict(x=108, w=104, h=62, wall="#7a5a3a", mat="logs", roof="steep", rc="#3f4f3a", door="#5a3a28",
                    win=[(126, 154)], feature="woodstack"),
    "morrow":  dict(x=84, w=152, h=104, wall="#c9a35a", mat="render", roof="gable", rc="#5f4a36", door="#2c3e5a",
                    win=[(104, 112), (186, 112)], feature="bay"),
    "okafor":  dict(x=80, w=160, h=80, wall="#ece2c8", mat="render", roof="gable", rc="#46524a", door="#2f6b4a",
                    win=[(100, 140), (190, 140)], feature="shutters_trellis"),
    "pryce":   dict(x=112, w=96, h=108, wall="#d8bf7a", mat="brick", roof="flat_parapet", rc="#5a4636", door="#a8322a",
                    win=[(126, 108), (176, 108)], feature="arch_window"),
    "vale":    dict(x=84, w=152, h=66, wall="#f2efe6", mat="render", roof="thatch", rc="#b89a5a", door="#4a6b8a",
                    win=[(102, 152), (190, 152)], feature="thatch"),
}


def _svg(body: str, w: int = W, h: int = H) -> str:
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{body}</svg>'


def _ground_shadow(x: float, w: float) -> str:
    return f'<ellipse cx="{x + w / 2}" cy="{G + 2}" rx="{w / 2 + 18}" ry="7" fill="#000000" opacity="0.28"/>'


def _material(mat: str, x, y, w, h, wall: str, worn: bool) -> str:
    line = shade(wall, 0.18)
    out = []
    if mat == "brick":
        for r, yy in enumerate(range(int(y) + 6, int(y + h), 8)):
            out.append(f'<path d="M {x} {yy} L {x + w} {yy}" stroke="{line}" stroke-width="1" opacity="0.55"/>')
            for xx in range(int(x) + (0 if r % 2 else 9), int(x + w), 18):
                out.append(f'<path d="M {xx} {yy - 8} L {xx} {yy}" stroke="{line}" stroke-width="1" opacity="0.45"/>')
    elif mat == "planks" or mat == "clapboard":
        step = 9 if mat == "clapboard" else 12
        for yy in range(int(y) + step, int(y + h), step):
            out.append(f'<path d="M {x} {yy} L {x + w} {yy}" stroke="{line}" stroke-width="1.4" opacity="0.6"/>')
    elif mat == "stone":
        for r, yy in enumerate(range(int(y), int(y + h), 14)):
            for xx in range(int(x) + (0 if r % 2 else 10), int(x + w) - 8, 22):
                out.append(f'<rect x="{xx + 1}" y="{yy + 1}" width="19" height="12" rx="3" fill="{shade(wall, 0.06 * ((xx + yy) % 3))}" '
                           f'stroke="{line}" stroke-width="0.8" opacity="0.8"/>')
    elif mat == "logs":
        for yy in range(int(y) + 6, int(y + h), 11):
            out.append(f'<path d="M {x} {yy} L {x + w} {yy}" stroke="{shade(wall, 0.3)}" stroke-width="2"/>'
                       f'<circle cx="{x + 2}" cy="{yy - 5}" r="5" fill="{shade(wall, -0.15)}" stroke="{shade(wall, 0.3)}"/>'
                       f'<circle cx="{x + w - 2}" cy="{yy - 5}" r="5" fill="{shade(wall, -0.15)}" stroke="{shade(wall, 0.3)}"/>')
    elif mat == "timber":
        beam = "#4a3426"
        out.append(f'<path d="M {x} {y + h / 2} L {x + w} {y + h / 2}" stroke="{beam}" stroke-width="5"/>')
        for xx in (x + 4, x + w / 2, x + w - 4):
            out.append(f'<path d="M {xx} {y} L {xx} {y + h}" stroke="{beam}" stroke-width="5"/>')
        out.append(f'<path d="M {x + 4} {y + h / 2} L {x + w / 2} {y + 4} L {x + w - 4} {y + h / 2}" stroke="{beam}" '
                   f'stroke-width="4" fill="none"/>')
    if worn and mat in ("render", "timber"):
        for (dx, dy, rw, rh) in [(0.15, 0.3, 18, 10), (0.7, 0.62, 22, 9), (0.42, 0.78, 14, 8)]:
            out.append(f'<ellipse cx="{x + w * dx}" cy="{y + h * dy}" rx="{rw}" ry="{rh}" fill="{shade(wall, 0.22)}" opacity="0.55"/>')
    return "".join(out)


def _roof(kind: str, x, y, w, rc: str, worn: bool, fine: bool) -> str:
    eave = 12
    out = []
    if kind in ("gable", "steep"):
        peak = y - (w * 0.38 if kind == "gable" else w * 0.55)
        out.append(f'<path d="M {x - eave} {y + 2} L {x + w / 2} {peak} L {x + w + eave} {y + 2} Z" fill="{rc}"/>')
        for i in range(1, 5):
            t = i / 5
            yy = peak + (y + 2 - peak) * t
            half = (w / 2 + eave) * t
            out.append(f'<path d="M {x + w / 2 - half} {yy} L {x + w / 2 + half} {yy}" stroke="{shade(rc, 0.25)}" '
                       f'stroke-width="1.2" opacity="0.6"/>')
        apex = (x + w / 2, peak)
    elif kind == "hip":
        peak = y - w * 0.22
        out.append(f'<path d="M {x - eave} {y + 2} L {x + w * 0.22} {peak} L {x + w * 0.78} {peak} L {x + w + eave} {y + 2} Z" fill="{rc}"/>')
        for i in range(1, 4):
            yy = peak + (y + 2 - peak) * i / 4
            out.append(f'<path d="M {x} {yy} L {x + w} {yy}" stroke="{shade(rc, 0.25)}" stroke-width="1.2" opacity="0.6"/>')
        apex = (x + w / 2, peak)
    elif kind == "thatch":
        peak = y - w * 0.36
        out.append(f'<path d="M {x - 16} {y + 8} Q {x + w / 2} {peak - 18} {x + w + 16} {y + 8} Q {x + w / 2} {y - 4} {x - 16} {y + 8} Z" fill="{rc}"/>')
        for i in range(0, int(w + 30), 7):
            out.append(f'<path d="M {x - 14 + i} {y + 6} l -3 -14" stroke="{shade(rc, 0.25)}" stroke-width="1.2" opacity="0.6"/>')
        apex = (x + w / 2, peak)
    else:  # flat with a parapet
        peak = y - 10
        out.append(f'<rect x="{x - 4}" y="{peak}" width="{w + 8}" height="12" fill="{rc}"/>'
                   f'<rect x="{x - 6}" y="{peak - 4}" width="{w + 12}" height="5" fill="{shade(rc, -0.15)}"/>')
        apex = (x + w / 2, peak)
    if worn:
        for (dx, dy) in [(0.3, 0.55), (0.62, 0.4), (0.75, 0.7)]:
            px = x + w * dx
            py = apex[1] + (y - apex[1]) * dy
            out.append(f'<path d="M {px} {py} l 12 -2 l 3 8 l -13 2 Z" fill="{shade(rc, -0.25)}" opacity="0.9"/>')
        out.append(f'<path d="M {x - eave} {y + 3} Q {x + w / 2} {y + 9} {x + w + eave} {y + 3}" stroke="{shade(rc, 0.3)}" '
                   f'stroke-width="3" fill="none"/>')  # sagging gutter
    elif fine:
        out.append(f'<path d="M {x - eave} {y + 3} L {x + w + eave} {y + 3}" stroke="#d8d2c2" stroke-width="3"/>')
    return "".join(out), apex


def _window(x, y, ww: float, hh: float, lit: bool, condition: str, arch: bool = False, shutters: str | None = None) -> str:
    glass = "#f2c45a" if lit else "#3a4250"
    frame = {"fine": "#f4f0e6", "tidy": "#ece6d8", "plain": "#cfc7b4", "worn": "#9a9282"}[condition]
    out = []
    if shutters:
        out.append(f'<rect x="{x - 9}" y="{y}" width="8" height="{hh}" fill="{shutters}"/>'
                   f'<rect x="{x + ww + 1}" y="{y}" width="8" height="{hh}" fill="{shutters}"/>')
    if arch:
        out.append(f'<path d="M {x} {y + hh} L {x} {y + ww / 2} A {ww / 2} {ww / 2} 0 0 1 {x + ww} {y + ww / 2} L {x + ww} {y + hh} Z" '
                   f'fill="{glass}" stroke="{frame}" stroke-width="3"/>')
    else:
        out.append(f'<rect x="{x}" y="{y}" width="{ww}" height="{hh}" fill="{glass}" stroke="{frame}" stroke-width="3"/>')
    out.append(f'<path d="M {x + ww / 2} {y} L {x + ww / 2} {y + hh} M {x} {y + hh / 2} L {x + ww} {y + hh / 2}" '
               f'stroke="{frame}" stroke-width="2"/>')
    if condition == "worn":
        out.append(f'<path d="M {x + 3} {y + 3} L {x + ww / 2 - 2} {y + hh / 2 - 2} M {x + ww / 2 + 2} {y + 4} l 6 8" '
                   f'stroke="#d8d4cc" stroke-width="1.2" opacity="0.8"/>')  # cracked pane
    if condition in ("fine", "tidy"):
        out.append(f'<path d="M {x + 2} {y + 2} Q {x + 6} {y + hh / 2} {x + 3} {y + hh - 2}" stroke="#e8dcc8" '
                   f'stroke-width="3" fill="none" opacity="0.8"/>')  # curtain
        flowers = ["#d9705f", "#e8c050", "#c86aa8"] if condition == "fine" else ["#d9705f", "#e8c050"]
        out.append(f'<rect x="{x - 3}" y="{y + hh}" width="{ww + 6}" height="6" fill="#7a5a3a"/>')
        for i, c in enumerate(flowers * 2):
            out.append(f'<circle cx="{x + 3 + i * (ww - 2) / 5}" cy="{y + hh - 1}" r="3" fill="{c}"/>')
    return "".join(out)


def house_svg(style: str, condition: str) -> str:
    h = HOUSES[style]
    worn, fine = condition == "worn", condition == "fine"
    wall = h["wall"]
    if condition == "plain":
        wall = mix(wall, "#8a8478", 0.18)
    elif condition == "worn":
        wall = mix(wall, "#6f6a60", 0.35)
    elif fine:
        wall = mix(wall, "#ffffff", 0.06)
    rc = mix(h["rc"], "#5a5650", 0.3) if worn else h["rc"]
    x, w, hh = h["x"], h["w"], h["h"]
    y = G - hh
    out = [_ground_shadow(x, w)]
    feat = h["feature"]
    roof, apex = _roof(h["roof"], x, y, w, rc, worn, fine)
    # chimney behind the roof
    cx = x + w * (0.78 if feat != "chimney_tall" else 0.82)
    ch_top = apex[1] - (26 if feat == "chimney_tall" else 8)
    out.append(f'<rect x="{cx - 8}" y="{ch_top}" width="16" height="{y - ch_top + 4}" fill="{shade(wall, 0.25) if h["mat"] != "brick" else shade(wall, 0.1)}"/>'
               f'<rect x="{cx - 10}" y="{ch_top - 4}" width="20" height="6" fill="{shade(rc, 0.2)}"/>')
    if not worn:
        out.append(f'<path d="M {cx} {ch_top - 6} q -8 -12 2 -22 q 10 -10 0 -22" stroke="#c8c4bc" stroke-width="4" fill="none" '
                   f'opacity="0.35" stroke-linecap="round"/>')
    if feat == "veranda" or feat == "porch":
        pass
    out.append(f'<rect x="{x}" y="{y}" width="{w}" height="{hh}" fill="{wall}"/>')
    out.append(_material(h["mat"], x, y, w, hh, wall, worn))
    out.append(roof)
    # features
    if feat == "carved_gable":
        out.append(f'<path d="M {x - 6} {y} L {x + w / 2} {apex[1] + 6} L {x + w + 6} {y}" stroke="#e8d8b0" stroke-width="3" '
                   f'fill="none" stroke-dasharray="6 3"/>')
    if feat == "round_window":
        out.append(f'<circle cx="{x + w / 2}" cy="{(y + apex[1]) / 2 + 8}" r="10" fill="#3a4250" stroke="#d8d2c2" stroke-width="3"/>')
    if feat == "dormer":
        dx = x + w * 0.62
        out.append(f'<path d="M {dx} {y - 4} L {dx} {y - 26} L {dx + 14} {y - 40} L {dx + 28} {y - 26} L {dx + 28} {y - 4} Z" '
                   f'fill="{wall}"/><path d="M {dx - 4} {y - 24} L {dx + 14} {y - 42} L {dx + 32} {y - 24}" stroke="{rc}" '
                   f'stroke-width="6" fill="none"/>' + _window(dx + 6, y - 24, 16, 16, False, condition))
    if feat == "bay":
        out.append(f'<path d="M {x + w / 2 - 34} {G} L {x + w / 2 - 30} {G - 52} L {x + w / 2 + 30} {G - 52} L {x + w / 2 + 34} {G} Z" '
                   f'fill="{shade(wall, -0.06)}"/>' + _window(x + w / 2 - 24, G - 46, 48, 28, True, condition)
                   + f'<path d="M {x + w / 2 - 36} {G - 52} L {x + w / 2 + 36} {G - 52}" stroke="{rc}" stroke-width="6"/>')
    # windows and door
    shutters = "#2f6b4a" if feat == "shutters_trellis" else None
    for i, (wx, wy) in enumerate(h["win"]):
        out.append(_window(wx, wy, 26 if style not in ("pryce",) else 22, 30, i % 2 == 0, condition,
                           arch=feat == "arch_window" and i == 0, shutters=shutters))
    dw, dh = 26, 44
    dx = x + w / 2 - dw / 2 if feat not in ("bay",) else x + 18
    if style == "ash":
        dx = x + w - 44
    door = h["door"] if not worn else mix(h["door"], "#6f6a60", 0.45)
    out.append(f'<rect x="{dx - 3}" y="{G - dh - 3}" width="{dw + 6}" height="{dh + 3}" fill="{shade(wall, 0.3)}"/>'
               f'<rect x="{dx}" y="{G - dh}" width="{dw}" height="{dh}" fill="{door}"/>'
               f'<circle cx="{dx + dw - 6}" cy="{G - dh / 2}" r="2" fill="#d6a640"/>'
               f'<rect x="{dx - 6}" y="{G - 2}" width="{dw + 12}" height="4" fill="#8a8478"/>')
    if worn:
        out.append(f'<path d="M {dx + 3} {G - dh + 8} L {dx + dw - 3} {G - dh + 14}" stroke="{shade(door, 0.3)}" stroke-width="2"/>')
    if fine:
        out.append(f'<rect x="{dx + dw + 6}" y="{G - dh - 6}" width="6" height="10" rx="2" fill="#d6a640"/>'
                   f'<circle cx="{dx + dw + 9}" cy="{G - dh + 8}" r="4" fill="#f2c45a" opacity="0.9"/>')  # brass lamp
    if feat == "porch":
        out.append(f'<path d="M {x + 20} {G - 58} L {x + w - 20} {G - 58} L {x + w - 10} {G - 70} L {x + 10} {G - 70} Z" fill="{rc}"/>')
        for px in (x + 24, x + w / 2 - 30, x + w / 2 + 30, x + w - 24):
            out.append(f'<rect x="{px - 3}" y="{G - 58}" width="6" height="58" fill="#e8e0cc"/>')
    if feat == "veranda":
        out.append(f'<path d="M {x - 6} {G - 52} L {x + w + 6} {G - 52} L {x + w + 12} {G - 62} L {x - 12} {G - 62} Z" fill="{rc}"/>')
        for px in range(int(x), int(x + w) + 1, int(w / 4)):
            out.append(f'<rect x="{px - 2}" y="{G - 52}" width="4" height="52" fill="#e8e0cc"/>')
        out.append(f'<path d="M {x} {G - 22} L {x + w} {G - 22}" stroke="#e8e0cc" stroke-width="3"/>')
    if feat == "shutters_trellis":
        out.append(f'<path d="M {x + 6} {G} L {x + 6} {G - 60} M {x + 14} {G} L {x + 14} {G - 60}" stroke="#7a5a3a" stroke-width="2"/>')
        if not worn:
            for i in range(6):
                out.append(f'<circle cx="{x + 10 + (i % 2) * 6}" cy="{G - 10 - i * 9}" r="4" fill="{["#d9705f", "#4f7a4a"][i % 2]}"/>')
    if feat == "woodstack":
        for i in range(3):
            for j in range(4 - i):
                out.append(f'<circle cx="{x + w + 18 + j * 10 + i * 5}" cy="{G - 6 - i * 9}" r="5" fill="#8a6a44" stroke="#5a4028"/>')
    if worn:
        out.append(f'<path d="M {x + w * 0.2} {y + 10} l 6 14 l -4 10 l 7 12" stroke="{shade(wall, 0.4)}" stroke-width="1.4" fill="none"/>')
        out.append(f'<g transform="rotate(-8 {x + 30} {G - 30})"><rect x="{x + 16}" y="{G - 36}" width="30" height="5" fill="#8a7a5a"/>'
                   f'<rect x="{x + 18}" y="{G - 26}" width="28" height="5" fill="#7a6a4a"/></g>')  # boards
    return _svg("".join(out))


def garden_svg(kind: str) -> str:
    out = []
    if kind == "neat":
        for x0 in (8, 236):
            out.append(f'<rect x="{x0}" y="{G - 22}" width="76" height="22" rx="10" fill="#3f6b3a"/>'
                       f'<rect x="{x0 + 4}" y="{G - 20}" width="68" height="6" rx="3" fill="#4f7f48" opacity="0.8"/>')
        for i in range(10):
            out.append(f'<circle cx="{14 + i * 7}" cy="{G - 25}" r="3" fill="{["#d9705f", "#e8c050", "#c86aa8"][i % 3]}"/>')
        out.append(f'<path d="M 0 {G + 1} L {W} {G + 1}" stroke="#4f7f48" stroke-width="3"/>')
    else:
        for i in range(0, W, 5):
            hgt = 10 + (i * 37 % 19)
            out.append(f'<path d="M {i} {G + 2} q {(i % 3) - 1} {-hgt / 2} {(i % 5) - 2} {-hgt}" stroke="{["#5a7a3a", "#6b8a44", "#4a6a32"][i % 3]}" '
                       f'stroke-width="2" fill="none"/>')
        for x0 in (20, 64, 250, 292):
            out.append(f'<circle cx="{x0}" cy="{G - 14}" r="9" fill="#4a6a32" opacity="0.9"/>'
                       f'<circle cx="{x0 + 3}" cy="{G - 22}" r="2.5" fill="#e8e0b0"/>')
    return _svg("".join(out))


def prop_svg(trade: str) -> str:
    """Something by the door that tells you what the household does (bottom right corner)."""
    x, y = 262, G
    out = []
    if trade == "mill_hand":
        out.append(f'<path d="M {x - 30} {y - 18} L {x + 10} {y - 18} L {x + 4} {y - 4} L {x - 24} {y - 4} Z" fill="#6b5a44"/>'
                   f'<circle cx="{x - 22}" cy="{y - 4}" r="5" fill="#3a3026"/><path d="M {x + 10} {y - 18} L {x + 30} {y - 26}" stroke="#6b5a44" stroke-width="3"/>'
                   f'<ellipse cx="{x - 14}" cy="{y - 24}" rx="12" ry="8" fill="#e6dcc4"/><ellipse cx="{x - 2}" cy="{y - 22}" rx="10" ry="7" fill="#d8ccb0"/>')
    elif trade == "mill_owner":
        out.append(f'<rect x="{x + 6}" y="{y - 60}" width="4" height="60" fill="#2a2a2e"/><path d="M {x} {y - 60} L {x + 16} {y - 60} L {x + 12} {y - 74} L {x + 4} {y - 74} Z" fill="#f2c45a" stroke="#2a2a2e" stroke-width="2"/>'
                   f'<path d="M {x - 34} {y} L {x - 30} {y - 20} L {x - 14} {y - 20} L {x - 10} {y} Z" fill="#8a8478"/><circle cx="{x - 22}" cy="{y - 26}" r="8" fill="#4f7a4a"/>')
    elif trade == "grocer":
        for i, c in enumerate(["#c84a3a", "#e8a040", "#5a8a3a"]):
            out.append(f'<rect x="{x - 36 + i * 4}" y="{y - 14 - i * 12}" width="34" height="12" fill="#a8844f" stroke="#6b5232"/>'
                       f'<circle cx="{x - 28 + i * 4}" cy="{y - 16 - i * 12}" r="3.5" fill="{c}"/><circle cx="{x - 18 + i * 4}" cy="{y - 16 - i * 12}" r="3.5" fill="{c}"/>')
    elif trade == "publican":
        for i in range(2):
            out.append(f'<ellipse cx="{x - 20 + i * 24}" cy="{y - 14}" rx="11" ry="14" fill="#7a5232" stroke="#3a2a1e" stroke-width="2"/>'
                       f'<path d="M {x - 31 + i * 24} {y - 20} L {x - 9 + i * 24} {y - 20} M {x - 31 + i * 24} {y - 8} L {x - 9 + i * 24} {y - 8}" stroke="#3a3026" stroke-width="2"/>')
    elif trade == "barhand":
        out.append(f'<rect x="{x - 30}" y="{y - 16}" width="40" height="16" fill="#8a6a44" stroke="#5a4028"/>')
        for i in range(5):
            out.append(f'<rect x="{x - 27 + i * 7}" y="{y - 30}" width="5" height="16" rx="2" fill="#3f6b4a"/>')
    elif trade == "nurse":
        out.append(f'<circle cx="{x - 24}" cy="{y - 8}" r="8" fill="none" stroke="#3a3a3e" stroke-width="2.5"/><circle cx="{x + 4}" cy="{y - 8}" r="8" fill="none" stroke="#3a3a3e" stroke-width="2.5"/>'
                   f'<path d="M {x - 24} {y - 8} L {x - 12} {y - 22} L {x + 4} {y - 8} M {x - 14} {y - 22} L {x - 8} {y - 30}" stroke="#4a6b8a" stroke-width="3" fill="none"/>'
                   f'<rect x="{x + 14}" y="{y - 16}" width="14" height="16" fill="#a8644a"/><circle cx="{x + 21}" cy="{y - 22}" r="7" fill="#5a8a4a"/>')
    elif trade == "mechanic":
        out.append(f'<circle cx="{x - 18}" cy="{y - 13}" r="13" fill="#2a2a2e"/><circle cx="{x - 18}" cy="{y - 13}" r="5" fill="#6a6a6e"/>'
                   f'<rect x="{x + 2}" y="{y - 24}" width="18" height="24" rx="2" fill="#7a3a2a"/><rect x="{x + 2}" y="{y - 20}" width="18" height="3" fill="#a8a8a8"/>')
    elif trade == "shop_assistant":
        out.append(f'<circle cx="{x - 26}" cy="{y - 10}" r="10" fill="none" stroke="#3a3a3e" stroke-width="2.5"/><circle cx="{x + 6}" cy="{y - 10}" r="10" fill="none" stroke="#3a3a3e" stroke-width="2.5"/>'
                   f'<path d="M {x - 26} {y - 10} L {x - 12} {y - 26} L {x + 6} {y - 10} M {x - 14} {y - 26} L {x - 18} {y - 32}" stroke="#a8322a" stroke-width="3" fill="none"/>')
    elif trade == "unemployed":
        out.append(f'<rect x="{x - 34}" y="{y - 4}" width="44" height="4" fill="#6b5a44"/><path d="M {x - 30} {y - 4} L {x - 8} {y - 30}" stroke="#6b5a44" stroke-width="3"/>'
                   f'<rect x="{x - 6}" y="{y - 22}" width="16" height="22" fill="#9a8a6a" opacity="0.9"/><path d="M {x - 4} {y - 22} L {x + 8} {y}" stroke="#6a5a3a" stroke-width="1.5"/>')
    elif trade == "retiree":
        out.append(f'<rect x="{x - 36}" y="{y - 16}" width="46" height="5" fill="#7a5a3a"/><rect x="{x - 34}" y="{y - 11}" width="4" height="11" fill="#5a4028"/><rect x="{x + 4}" y="{y - 11}" width="4" height="11" fill="#5a4028"/>'
                   f'<rect x="{x - 36}" y="{y - 30}" width="46" height="4" fill="#7a5a3a"/><ellipse cx="{x - 10}" cy="{y - 22}" rx="8" ry="5" fill="#3a3a3e"/><circle cx="{x - 3}" cy="{y - 26}" r="4" fill="#3a3a3e"/>'
                   f'<path d="M {x - 18} {y - 22} q -6 -8 -2 -12" stroke="#3a3a3e" stroke-width="2" fill="none"/>')
    return _svg("".join(out))


# ------------------------------------------------------------------ workplaces and public places
def _sign(x, y, w, text: str, col="#2a2118", bg="#d8c8a0", size=13) -> str:
    return (f'<rect x="{x}" y="{y}" width="{w}" height="22" rx="3" fill="{bg}" stroke="{col}" stroke-width="2"/>'
            f'<text x="{x + w / 2}" y="{y + 16}" font-family="Georgia, serif" font-size="{size}" font-weight="bold" '
            f'text-anchor="middle" fill="{col}" letter-spacing="1">{text}</text>')


def place_svg(kind: str, variant: str = "") -> str:
    out = []
    if kind == "shop":
        x, w, hh = 66, 188, 104
        out.append(_ground_shadow(x, w))
        out.append(f'<rect x="{x}" y="{G - hh}" width="{w}" height="{hh}" fill="#c9b38a"/>')
        out.append(_material("brick", x, G - hh, w, hh, "#c9b38a", False))
        out.append(f'<rect x="{x - 6}" y="{G - hh - 14}" width="{w + 12}" height="16" fill="#5a4636"/>')
        out.append(_sign(x + 34, G - hh + 4, w - 68, "GROCERY"))
        for i in range(8):  # striped awning
            c = "#3f6b52" if i % 2 == 0 else "#efe7d8"
            out.append(f'<path d="M {x - 4 + i * (w + 8) / 8} {G - 68} L {x - 4 + (i + 1) * (w + 8) / 8} {G - 68} '
                       f'L {x - 4 + (i + 1) * (w + 8) / 8} {G - 52} L {x - 4 + i * (w + 8) / 8} {G - 52} Z" fill="{c}"/>')
        out.append(f'<path d="M {x - 4} {G - 52} q 12 8 {(w + 8) / 8} 0 q 12 8 {(w + 8) / 8} 0 q 12 8 {(w + 8) / 8} 0 q 12 8 {(w + 8) / 8} 0 '
                   f'q 12 8 {(w + 8) / 8} 0 q 12 8 {(w + 8) / 8} 0 q 12 8 {(w + 8) / 8} 0 q 12 8 {(w + 8) / 8} 0" fill="#3f6b52"/>')
        out.append(f'<rect x="{x + 12}" y="{G - 46}" width="84" height="40" fill="#f2c45a" stroke="#5a4636" stroke-width="3"/>'
                   f'<rect x="{x + 112}" y="{G - 48}" width="30" height="48" fill="#3f6b52" stroke="#5a4636" stroke-width="3"/>')
        out.append(prop_svg("grocer")[prop_svg("grocer").index(">") + 1:-6].replace(f"{262}", "262"))
        for i, c in enumerate(["#c84a3a", "#e8a040", "#5a8a3a", "#c84a3a"]):
            out.append(f'<circle cx="{x + 22 + i * 18}" cy="{G - 14}" r="6" fill="{c}"/>')
    elif kind == "pub":
        x, w, hh = 70, 180, 112
        out.append(_ground_shadow(x, w))
        out.append(f'<rect x="{x}" y="{G - hh}" width="{w}" height="{hh}" fill="#b89a74"/>')
        out.append(_material("timber", x, G - hh, w, hh, "#b89a74", False))
        roof, apex = _roof("gable", x, G - hh, w, "#5a3a2e", False, False)
        out.append(roof)
        for wx in (x + 16, x + w - 46):
            out.append(_window(wx, G - 50, 30, 26, True, "tidy"))
        out.append(f'<rect x="{x + w / 2 - 16}" y="{G - 50}" width="32" height="50" fill="#5a2f2a"/>'
                   f'<path d="M {x + w / 2 - 16} {G - 50} A 16 12 0 0 1 {x + w / 2 + 16} {G - 50}" fill="#5a2f2a"/>')
        out.append(f'<path d="M {x + w + 2} {G - 92} L {x + w + 34} {G - 92}" stroke="#2a2a2e" stroke-width="4"/>'
                   f'<rect x="{x + w + 8}" y="{G - 90}" width="26" height="34" rx="3" fill="#d8c8a0" stroke="#2a2118" stroke-width="2"/>')
        icon = {"drovers_rest": f'<path d="M {x + w + 14} {G - 64} L {x + w + 20} {G - 84} Q {x + w + 26} {G - 86} {x + w + 26} {G - 80}" '
                                f'stroke="#5a3a28" stroke-width="2.5" fill="none"/>',
                "crooked_pike": f'<path d="M {x + w + 10} {G - 72} Q {x + w + 21} {G - 82} {x + w + 32} {G - 72} Q {x + w + 21} {G - 64} {x + w + 10} {G - 72} Z" '
                                f'fill="#4f6a7a"/><path d="M {x + w + 10} {G - 72} l -3 -4 l 0 8 Z" fill="#4f6a7a"/>',
                "lantern": f'<rect x="{x + w + 16}" y="{G - 82}" width="10" height="16" fill="#f2c45a" stroke="#2a2a2e" stroke-width="2"/>'
                           f'<path d="M {x + w + 14} {G - 82} L {x + w + 21} {G - 88} L {x + w + 28} {G - 82}" fill="#2a2a2e"/>',
                "grey_heron": f'<path d="M {x + w + 22} {G - 62} L {x + w + 22} {G - 74} Q {x + w + 14} {G - 80} {x + w + 22} {G - 86} '
                              f'L {x + w + 30} {G - 84}" stroke="#6a6e74" stroke-width="3" fill="none"/>'
                              f'<ellipse cx="{x + w + 19}" cy="{G - 72}" rx="6" ry="4" fill="#8a8e94"/>'}.get(variant, "")
        out.append(icon or f'<circle cx="{x + w + 21}" cy="{G - 73}" r="7" fill="#d9a441"/>')
        out.append(prop_svg("publican")[prop_svg("publican").index(">") + 1:-6])
    elif kind == "mill":
        x, w, hh = 50, 170, 130
        out.append(_ground_shadow(x, w + 40))
        out.append(f'<rect x="{x + w - 6}" y="{G - 10}" width="110" height="12" fill="#4f7f9a" opacity="0.8"/>')
        out.append(f'<rect x="{x}" y="{G - hh}" width="{w}" height="{hh}" fill="#a39c90"/>')
        out.append(_material("stone", x, G - hh, w, hh, "#a39c90", False))
        roof, apex = _roof("gable", x, G - hh, w, "#4f5a63", False, False)
        out.append(roof)
        for r in range(2):
            for c in range(3):
                out.append(_window(x + 22 + c * 50, G - hh + 20 + r * 46, 22, 26, (r + c) % 3 == 0, "plain"))
        out.append(f'<rect x="{x + w / 2 - 22}" y="{G - 52}" width="44" height="52" fill="#5a4636"/>')
        wx, wy, rr = x + w + 30, G - 40, 40
        out.append(f'<circle cx="{wx}" cy="{wy}" r="{rr}" fill="none" stroke="#6b5232" stroke-width="7"/>')
        for i in range(8):
            import math
            a = i * math.pi / 4
            out.append(f'<path d="M {wx} {wy} L {wx + rr * math.cos(a)} {wy + rr * math.sin(a)}" stroke="#6b5232" stroke-width="4"/>'
                       f'<rect x="{wx + rr * math.cos(a) - 6}" y="{wy + rr * math.sin(a) - 4}" width="12" height="8" fill="#7a6040" '
                       f'transform="rotate({i * 45} {wx + rr * math.cos(a)} {wy + rr * math.sin(a)})"/>')
        out.append(f'<circle cx="{wx}" cy="{wy}" r="7" fill="#3a3026"/>')
        out.append(_sign(x + 30, G - hh + 2 - 26, 110, "THE MILL", size=12))
    elif kind == "clinic":
        x, w, hh = 76, 168, 96
        out.append(_ground_shadow(x, w))
        out.append(f'<rect x="{x}" y="{G - hh}" width="{w}" height="{hh}" fill="#efede6"/>')
        roof, apex = _roof("hip", x, G - hh, w, "#46524a", False, True)
        out.append(roof)
        out.append(_sign(x + 40, G - hh + 8, w - 80, "CLINIC"))
        out.append(f'<path d="M {x + w / 2 - 50} {G - hh + 19} m -4 0 h 8 m -4 -4 v 8" stroke="#2f8a5a" stroke-width="3"/>')
        for wx in (x + 16, x + w - 44):
            out.append(_window(wx, G - 62, 28, 30, False, "fine"))
        out.append(f'<rect x="{x + w / 2 - 15}" y="{G - 50}" width="30" height="50" fill="#4a6b8a"/>'
                   f'<rect x="{x + w / 2 - 26}" y="{G - 4}" width="52" height="4" fill="#cfc7b4"/><rect x="{x + w / 2 - 22}" y="{G - 8}" width="44" height="4" fill="#ddd6c4"/>')
        out.append(f'<rect x="{x + w + 10}" y="{G - 54}" width="4" height="54" fill="#2a2a2e"/><circle cx="{x + w + 12}" cy="{G - 58}" r="6" fill="#f2c45a"/>')
    elif kind == "workshop":
        x, w, hh = 56, 208, 92
        out.append(_ground_shadow(x, w))
        out.append(f'<rect x="{x}" y="{G - hh}" width="{w}" height="{hh}" fill="#8a8e8a"/>')
        out.append(_material("planks", x, G - hh, w, hh, "#8a8e8a", False))
        out.append(f'<path d="M {x - 8} {G - hh + 4} L {x + w / 2} {G - hh - 26} L {x + w + 8} {G - hh + 4} Z" fill="#5a4a3a"/>')
        out.append(_sign(x + 50, G - hh - 4, w - 100, "WORKSHOP", size=12))
        out.append(f'<rect x="{x + 14}" y="{G - 64}" width="80" height="64" fill="#1e1c1a"/><rect x="{x + 14}" y="{G - 64}" width="80" height="20" fill="#6a6e6a"/>'
                   f'<rect x="{x + 110}" y="{G - 64}" width="80" height="64" fill="#6a6e6a"/>')
        for i in range(5):
            out.append(f'<path d="M {x + 110} {G - 56 + i * 12} L {x + 190} {G - 56 + i * 12}" stroke="#4a4e4a" stroke-width="2"/>')
        for i in range(3):
            out.append(f'<circle cx="{x + w + 14}" cy="{G - 10 - i * 14}" r="9" fill="#2a2a2e"/><circle cx="{x + w + 14}" cy="{G - 10 - i * 14}" r="3" fill="#6a6a6e"/>')
        out.append(f'<rect x="{x + 40}" y="{G - 28}" width="20" height="28" rx="3" fill="#a8322a"/><rect x="{x + 40}" y="{G - 22}" width="20" height="3" fill="#cfc7b4"/>')
    elif kind == "square":
        out.append(f'<ellipse cx="{W / 2}" cy="{G - 6}" rx="150" ry="22" fill="#6a6458"/>')
        for i in range(0, 300, 14):
            out.append(f'<path d="M {10 + i} {G - 10 + (i % 3) * 4} l 10 0" stroke="#55504a" stroke-width="2"/>')
        out.append(f'<ellipse cx="{W / 2}" cy="{G - 14}" rx="44" ry="11" fill="#8a8478"/><ellipse cx="{W / 2}" cy="{G - 18}" rx="36" ry="8" fill="#4f7f9a"/>'
                   f'<rect x="{W / 2 - 5}" y="{G - 62}" width="10" height="44" fill="#9a948a"/><ellipse cx="{W / 2}" cy="{G - 62}" rx="16" ry="5" fill="#8a8478"/>'
                   f'<path d="M {W / 2} {G - 66} q -12 10 -16 26 M {W / 2} {G - 66} q 12 10 16 26" stroke="#a8d0e0" stroke-width="2" fill="none" opacity="0.8"/>')
        out.append(f'<rect x="52" y="{G - 90}" width="5" height="78" fill="#2a2a2e"/><path d="M 46 {G - 96} L 63 {G - 96} L 60 {G - 108} L 49 {G - 108} Z" fill="#f2c45a" stroke="#2a2a2e" stroke-width="2"/>')
        out.append(f'<rect x="236" y="{G - 66}" width="50" height="38" fill="#7a5a3a"/><rect x="240" y="{G - 62}" width="42" height="30" fill="#e8dcc0"/>'
                   f'<rect x="244" y="{G - 58}" width="16" height="12" fill="#f4efe4"/><rect x="262" y="{G - 54}" width="16" height="16" fill="#efe4c8"/>'
                   f'<rect x="246" y="{G - 28}" width="4" height="22" fill="#5a4028"/><rect x="272" y="{G - 28}" width="4" height="22" fill="#5a4028"/>')
        out.append(f'<rect x="84" y="{G - 26}" width="44" height="5" fill="#7a5a3a"/><rect x="88" y="{G - 21}" width="4" height="10" fill="#4a3a2a"/><rect x="120" y="{G - 21}" width="4" height="10" fill="#4a3a2a"/>')
        out.append(f'<rect x="190" y="{G - 70}" width="8" height="56" fill="#4a3a2a"/><circle cx="194" cy="{G - 84}" r="26" fill="#3c4f33"/><circle cx="180" cy="{G - 74}" r="16" fill="#46593c"/>')
    elif kind == "road":
        out.append(f'<path d="M 0 {G - 4} C 80 {G - 30} 200 {G + 4} {W} {G - 26} L {W} {G + 8} C 200 {G + 22} 80 {G - 6} 0 {G + 18} Z" fill="#6b5f4e"/>')
        out.append(f'<path d="M 0 {G + 7} C 80 {G - 18} 200 {G + 13} {W} {G - 9}" stroke="#857760" stroke-width="2" stroke-dasharray="8 8" fill="none"/>')
        for i in range(9):
            out.append(f'<rect x="{12 + i * 36}" y="{G - 60 + (i % 2) * 2}" width="5" height="30" fill="#e8e0cc"/>')
        out.append(f'<path d="M 8 {G - 52} L 316 {G - 52} M 8 {G - 40} L 316 {G - 40}" stroke="#e8e0cc" stroke-width="3"/>')
        out.append(f'<path d="M 230 {G - 2} q 6 -16 2 -26 M 240 {G} q 2 -14 6 -22 M 250 {G - 2} q -4 -14 0 -24" stroke="#5a7a3a" stroke-width="2.5" fill="none"/>')
        out.append(f'<rect x="150" y="{G - 98}" width="5" height="70" fill="#5a4028"/><path d="M 156 {G - 96} L 214 {G - 96} L 224 {G - 88} L 214 {G - 80} L 156 {G - 80} Z" fill="#d8c8a0" stroke="#2a2118" stroke-width="2"/>'
                   f'<text x="186" y="{G - 84}" font-family="Georgia, serif" font-size="10" font-weight="bold" text-anchor="middle" fill="#2a2118">MILL RD</text>')
        out.append(f'<path d="M 92 {G + 2} L 100 {G - 22} L 112 {G - 22} L 120 {G + 2} Z" fill="#9a948a"/><text x="110" y="{G - 6}" font-family="Georgia, serif" font-size="9" text-anchor="middle" fill="#3a3630">1</text>')
    return _svg("".join(out))
