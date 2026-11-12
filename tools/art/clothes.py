"""Clothing templates, one per occupation: shoulders and collar, drawn over a portrait's neck (256x256)."""

from __future__ import annotations

from portraits import CX, shade

ROLES = ["mill_hand", "mill_owner", "grocer", "shop_assistant", "publican", "barhand", "nurse", "mechanic",
         "unemployed", "retiree"]


def _shoulders(col: str, neck: float = 27, top: float = 200) -> str:
    return (f'<path d="M 0 256 L 0 238 C 6 222 30 212 {CX - neck - 26} {top + 6} C {CX - neck - 8} {top} '
            f'{CX - neck} {top - 4} {CX - neck + 2} {top - 6} L {CX + neck - 2} {top - 6} C {CX + neck} {top - 4} '
            f'{CX + neck + 8} {top} {CX + neck + 26} {top + 6} C 226 212 250 222 256 238 L 256 256 Z" fill="{col}"/>'
            f'<path d="M 30 226 C 50 220 70 214 {CX - 40} 210" stroke="{shade(col, -0.12)}" stroke-width="2" '
            f'fill="none" opacity="0.5"/>')


def _v_collar(col: str, depth: float = 236, width: float = 26) -> str:
    return f'<path d="M {CX - width} 194 L {CX} {depth} L {CX + width} 194 Z" fill="{col}"/>'


def clothes_svg(role: str) -> str:
    p = ['<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">']
    if role == "mill_hand":
        shirt = "#7a6a4f"
        p.append(_shoulders(shirt))
        p.append(f'<path d="M {CX - 27} 194 L {CX - 10} 222 L {CX} 206 L {CX + 10} 222 L {CX + 27} 194 Z" fill="{shade(shirt, -0.12)}"/>')
        for side in (-1, 1):  # braces
            p.append(f'<path d="M {CX + side * 44} 256 L {CX + side * 40} 204" stroke="#3d2c1e" stroke-width="7"/>'
                     f'<rect x="{CX + side * 40 - 5}" y="226" width="10" height="7" fill="#b8a070"/>')
        p.append(f'<circle cx="{CX}" cy="236" r="2.5" fill="#3a3026"/><circle cx="{CX}" cy="250" r="2.5" fill="#3a3026"/>')
        p.append('<path d="M 20 246 l 12 -4 M 210 244 l 14 3" stroke="#e8e0d0" stroke-width="2" opacity="0.35"/>')  # flour dust
    elif role == "mill_owner":
        coat = "#2c3442"
        p.append(_shoulders(coat))
        p.append(f'<path d="M {CX - 30} 196 L {CX} 256 L {CX + 30} 196 Z" fill="#f2efe8"/>')
        p.append(f'<path d="M {CX - 12} 198 L {CX} 214 L {CX + 12} 198 L {CX + 6} 196 L {CX} 204 L {CX - 6} 196 Z" fill="#f8f6f0"/>')
        p.append(f'<path d="M {CX - 5} 206 L {CX + 5} 206 L {CX + 7} 250 L {CX} 256 L {CX - 7} 250 Z" fill="#6b2a2e"/>')
        p.append(f'<path d="M {CX - 30} 196 L {CX - 6} 256 L {CX - 46} 256 L {CX - 50} 214 Z" fill="{shade(coat, 0.15)}"/>'
                 f'<path d="M {CX + 30} 196 L {CX + 6} 256 L {CX + 46} 256 L {CX + 50} 214 Z" fill="{shade(coat, 0.15)}"/>')
        p.append(f'<path d="M {CX + 58} 236 Q {CX + 70} 242 {CX + 80} 238" stroke="#d6a640" stroke-width="2" fill="none"/>')
    elif role == "grocer":
        shirt = "#d8d2c2"
        p.append(_shoulders(shirt))
        for i in range(-5, 6):  # stripes
            p.append(f'<path d="M {CX + i * 22} 256 L {CX + i * 22 + 4} 200" stroke="#8aa0b8" stroke-width="3" opacity="0.6"/>')
        p.append(f'<path d="M {CX - 24} 194 L {CX} 214 L {CX + 24} 194 Z" fill="{shade(shirt, 0.1)}"/>')
        apron = "#3f6b52"
        p.append(f'<path d="M {CX - 46} 230 L {CX + 46} 230 L {CX + 50} 256 L {CX - 50} 256 Z" fill="{apron}"/>')
        for side in (-1, 1):
            p.append(f'<path d="M {CX + side * 40} 232 L {CX + side * 24} 196" stroke="{apron}" stroke-width="7"/>')
    elif role == "shop_assistant":
        card = "#9a5a4a"
        p.append(_shoulders(card))
        p.append(_v_collar("#efe7d8", 246, 30))
        p.append(f'<path d="M {CX - 14} 196 L {CX} 206 L {CX + 14} 196" stroke="#cfc4b0" stroke-width="3" fill="none"/>')
        for y in (226, 242):
            p.append(f'<circle cx="{CX + 30}" cy="{y}" r="3" fill="#e6d9b8"/>')
        p.append(f'<path d="M {CX + 30} 196 L {CX + 30} 256" stroke="{shade(card, 0.2)}" stroke-width="2"/>')
    elif role == "publican":
        shirt = "#ece6da"
        p.append(_shoulders(shirt))
        vest = "#5a2f2a"
        p.append(f'<path d="M {CX - 60} 256 L {CX - 50} 214 L {CX - 18} 200 L {CX} 248 L {CX + 18} 200 L {CX + 50} 214 L {CX + 60} 256 Z" fill="{vest}"/>')
        p.append(f'<path d="M {CX - 14} 198 L {CX - 2} 204 L {CX - 14} 210 Z M {CX + 14} 198 L {CX + 2} 204 L {CX + 14} 210 Z" fill="#2a2a2e"/>'
                 f'<circle cx="{CX}" cy="204" r="3" fill="#2a2a2e"/>')
        for y in (222, 236):
            p.append(f'<circle cx="{CX - 8}" cy="{y}" r="2.4" fill="#d6a640"/>')
    elif role == "barhand":
        shirt = "#4f6a7a"
        p.append(_shoulders(shirt))
        p.append(f'<path d="M {CX - 26} 194 L {CX - 8} 220 L {CX} 204 L {CX + 8} 220 L {CX + 26} 194 Z" fill="{shade(shirt, -0.15)}"/>')
        p.append(f'<path d="M {CX + 48} 206 L {CX + 92} 222 L {CX + 86} 256 L {CX + 52} 256 Z" fill="#e8e2d4"/>'
                 f'<path d="M {CX + 52} 214 L {CX + 90} 230 M {CX + 54} 226 L {CX + 88} 240" stroke="#c84a3a" stroke-width="2.5"/>')
    elif role == "nurse":
        uni = "#a8c4d8"
        p.append(_shoulders(uni))
        p.append(f'<path d="M {CX - 30} 194 L {CX} 222 L {CX + 30} 194 L {CX + 18} 214 L {CX} 230 L {CX - 18} 214 Z" fill="#f4f2ee"/>')
        p.append(f'<rect x="{CX + 34}" y="226" width="16" height="10" rx="2" fill="#f4f2ee"/>'
                 f'<path d="M {CX + 38} 231 L {CX + 46} 231" stroke="#3a6a8a" stroke-width="2"/>')
        p.append(f'<path d="M {CX - 70} 228 C {CX - 50} 250 {CX - 30} 254 {CX - 22} 238" stroke="#4a5058" stroke-width="2.5" fill="none"/>'
                 f'<circle cx="{CX - 22}" cy="236" r="4" fill="#9aa0a8"/>')  # stethoscope
    elif role == "mechanic":
        ov = "#3f5a7a"
        p.append(_shoulders(ov))
        p.append(f'<path d="M {CX - 24} 194 L {CX} 218 L {CX + 24} 194 Z" fill="#6a7a84"/>')
        p.append(f'<rect x="{CX - 22}" y="228" width="26" height="20" rx="3" fill="{shade(ov, 0.15)}"/>'
                 f'<path d="M {CX - 16} 228 L {CX - 16} 222" stroke="#c0c4c8" stroke-width="3"/>')
        for (x, y, r) in [(CX + 40, 232, 6), (CX + 52, 244, 4), (CX - 60, 240, 5)]:
            p.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="#1e1a18" opacity="0.35"/>')  # grease
        p.append(f'<path d="M {CX + 26} 200 L {CX + 26} 256" stroke="{shade(ov, 0.25)}" stroke-width="2"/>')
    elif role == "unemployed":
        knit = "#6b6a5a"
        p.append(_shoulders(knit))
        p.append(f'<path d="M {CX - 28} 196 Q {CX} 214 {CX + 28} 196 L {CX + 26} 206 Q {CX} 224 {CX - 26} 206 Z" fill="{shade(knit, 0.15)}"/>')
        for i in range(0, 256, 9):
            p.append(f'<path d="M {i} 256 L {i + 3} 230" stroke="{shade(knit, 0.12)}" stroke-width="1.4" opacity="0.6"/>')
        p.append(f'<rect x="{CX + 40}" y="226" width="20" height="16" rx="3" fill="#8a7a5a"/>'  # patch
                 f'<path d="M {CX + 42} 228 l 16 12 M {CX + 58} 228 l -16 12" stroke="#5a4a32" stroke-width="1" opacity="0.6"/>')
        p.append(f'<path d="M {CX - 70} 232 l 6 6 M {CX - 64} 232 l -6 6" stroke="#4a4a3a" stroke-width="1.5"/>')  # darn
    elif role == "retiree":
        cardi = "#7a6a8a"
        p.append(_shoulders(cardi))
        p.append(_v_collar("#e8e0cc", 250, 28))
        scarf = "#a85a3a"
        p.append(f'<path d="M {CX - 32} 194 Q {CX} 216 {CX + 32} 194 L {CX + 34} 206 Q {CX} 230 {CX - 34} 206 Z" fill="{scarf}"/>'
                 f'<path d="M {CX + 14} 210 L {CX + 24} 256 L {CX + 8} 256 L {CX + 4} 214 Z" fill="{shade(scarf, 0.12)}"/>')
        for y in (232, 248):
            p.append(f'<circle cx="{CX - 30}" cy="{y}" r="3" fill="#d8ccb0"/>')
    p.append("</svg>")
    return "".join(p)
