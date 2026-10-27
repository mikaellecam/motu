"""Motu's logo: the app's developed island, drawn like the map (BRIEF §10, MapPalette, iso.dart's
2:1 projection). Writes three 1024x1024 SVGs next to this file; icons.sh renders the app's icons from them.

    python3 docs/brand/motu.py && docs/brand/icons.sh
"""
import pathlib

OUT = pathlib.Path(__file__).parent

INK, SEA = "#1D2340", "#86D9EC"
SAND, SEAM = "#F4DE9C", "#6FB565"
GRASS = ("#8ED081", "#84C877")
DIRT = {"left": "#B57B45", "right": "#D79A5E"}
LEAVES = {"top": "#5FC26A", "left": "#33893F", "right": "#46A852"}
TRUNK = {"top": "#9A6A3C", "left": "#7A5230", "right": "#8A5E36"}
BUILDINGS = {
    "blue": ({"top": "#DCE6FF", "left": "#3F63D1", "right": "#5B82F2"}, "#BCD0FF"),
    "yellow": ({"top": "#FFF1C9", "left": "#E9A92A", "right": "#FFC845"}, "#FFFFFF"),
    "coral": ({"top": "#FFE0D6", "left": "#E25E3F", "right": "#FF7D5C"}, "#FFB4A0"),
    "teal": ({"top": "#E3F7F3", "left": "#2FA38A", "right": "#4CC3A9"}, "#A6E5D6"),
}
WINDOW, FLAG = "#FFF4C2", "#FF7D5C"

T = 100.0  # tile width in world-to-screen px before fitting; one height unit is T / 2


def P(x, y, z=0.0):
    return ((x - y) * T / 2, (x + y) * T / 4 - z * T / 2)


shapes = []  # (points, fill, stroke, stroke_width) in painting order


def poly(pts, fill, stroke=INK, sw=1.0):
    shapes.append(([P(*p) for p in pts], fill, stroke, sw))


def box(x, y, w, d, h, shades, z=0.0, top_stroke=INK, top_sw=1.0):
    poly([(x, y + d, z), (x + w, y + d, z), (x + w, y + d, z + h), (x, y + d, z + h)], shades["left"])
    poly([(x + w, y, z), (x + w, y + d, z), (x + w, y + d, z + h), (x + w, y, z + h)], shades["right"])
    poly([(x, y, z + h), (x + w, y, z + h), (x + w, y + d, z + h), (x, y + d, z + h)], shades["top"],
         top_stroke, top_sw)


def windows(x, y, w, d, h, lit, seed):
    """Two columns per visible side, a row every half unit; one window in three lit."""
    size, step, start = 0.25, 0.5, 0.28
    rows = int((h - start - 0.12) / step) + 1
    for r in range(rows):
        z0 = start + r * step
        for c in range(2):
            a = 0.18 + c * 0.38
            color = lit if (seed + r + c) % 3 == 0 else WINDOW
            # left side (plane y + d), along x
            poly([(x + a * w, y + d, z0), (x + (a + 0.22) * w, y + d, z0),
                  (x + (a + 0.22) * w, y + d, z0 + size), (x + a * w, y + d, z0 + size)], color, "none", 0)
            # right side (plane x + w), along y
            poly([(x + w, y + a * d, z0), (x + w, y + (a + 0.22) * d, z0),
                  (x + w, y + (a + 0.22) * d, z0 + size), (x + w, y + a * d, z0 + size)], color, "none", 0)


def building(cx, cy, h, color, seed, fp=0.78, flag=False):
    shades, lit = BUILDINGS[color]
    x, y = cx - fp / 2, cy - fp / 2
    box(x, y, fp, fp, h, shades)
    windows(x, y, fp, fp, h, lit, seed)
    if flag:
        top = (cx, cy, h)
        pole = (cx, cy, h + 1.3)
        shapes.append(([P(*top), P(*pole)], "none", INK, 1.0))
        px, py = P(*pole)
        shapes.append(([(px, py), (px + 0.46 * T, py + 0.15 * T), (px, py + 0.3 * T)], FLAG, INK, 1.0))


def tree(cx, cy, c=0.48, crown=0.46, trunk=0.34):
    t = 0.14
    box(cx - t / 2, cy - t / 2, t, t, trunk, TRUNK)
    box(cx - c / 2, cy - c / 2, c, c, crown, LEAVES, z=trunk)


def island():
    tiles = [(x, y) for y in range(4) for x in range(5) if (x, y) not in {(0, 3), (4, 0)}]
    grass = {(0, 0), (0, 1), (1, 0), (1, 1), (0, 2), (1, 2), (1, 3), (2, 3)}
    for x, y in sorted(tiles, key=lambda t: (t[0] + t[1], t[0])):
        top = GRASS[(x + y) % 2] if (x, y) in grass else SAND
        box(x, y, 1, 1, 0.7, {"top": top, **DIRT}, z=-0.7, top_stroke=SEAM, top_sw=0.35)
    things = [
        ((1.0, 0.8), lambda: tree(1.0, 0.8)),
        ((0.5, 1.4), lambda: tree(0.5, 1.4)),
        ((1.3, 3.2), lambda: tree(1.3, 3.2)),
        ((3.7, 3.2), lambda: tree(3.7, 3.2)),
        ((2.2, 0.7), lambda: building(2.2, 0.7, 2.2, "teal", 1, fp=0.72)),
        ((3.0, 1.9), lambda: building(3.0, 1.9, 1.4, "coral", 2, fp=0.72)),
        ((1.9, 1.9), lambda: building(1.9, 1.9, 0.8, "yellow", 0, fp=0.72)),
        ((3.2, 0.6), lambda: building(3.2, 0.6, 3.4, "blue", 3, fp=0.72, flag=True)),
    ]
    for _, draw in sorted(things, key=lambda t: t[0][0] + t[0][1]):
        draw()


def render(name, box_px, sea=True, cy=540):
    """The island fitted in box_px, centred; on the sea with its waves, or on transparency."""
    shapes.clear()
    island()
    xs = [p[0] for s in shapes for p in s[0]]
    ys = [p[1] for s in shapes for p in s[0]]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    k = box_px / max(x1 - x0, y1 - y0)
    ox, oy = 512 - (x0 + x1) / 2 * k, cy - (y0 + y1) / 2 * k
    stroke = 9.0 * box_px / 600

    def tr(p):
        return f"{ox + p[0] * k:.1f},{oy + p[1] * k:.1f}"

    body = f'<rect width="1024" height="1024" fill="{SEA}"/>' if sea else ""
    # The halo the map draws under an island, from its foot.
    foot = [P(1, 4), P(5, 4), P(5, 1)]
    fy = oy + max(p[1] for p in foot) * k
    body += (f'<ellipse cx="{512 + 10 * box_px / 600:.1f}" cy="{fy - 0.2 * T * k:.1f}" '
             f'rx="{(x1 - x0) * k * 0.62:.1f}" ry="{T * k * 0.95:.1f}" fill="#FFFFFF" fill-opacity="0.35"/>')
    if sea:
        for wx, wy, op in [(150, 200, 0.6), (820, 190, 0.6), (140, 860, 0.5), (830, 880, 0.5)]:
            body += (f'<path d="M{wx} {wy} q14 -11 28 0 t28 0" fill="none" stroke="#FFFFFF" '
                     f'stroke-opacity="{op}" stroke-width="12" stroke-linecap="round"/>')
    for pts, fill, st, sw in shapes:
        stroke_attr = "" if st == "none" else (
            f' stroke="{st}" stroke-width="{stroke * sw:.1f}" stroke-linejoin="round" stroke-linecap="round"')
        tag = "polyline" if fill == "none" else "polygon"
        body += f'<{tag} points="{" ".join(tr(p) for p in pts)}" fill="{fill}"{stroke_attr}/>'
    (OUT / f"{name}.svg").write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">{body}</svg>\n')


# The icon, as chosen on 2026-10-27 (M10-4).
render("motu-icon", 600)
# Android's adaptive foreground: a 108 dp layer whose launcher mask keeps at least the central 66 dp.
render("motu-foreground", 520, sea=False, cy=530)
# The splash: the island alone, on the sea the launch screen paints.
render("motu-island", 940, sea=False, cy=512)
