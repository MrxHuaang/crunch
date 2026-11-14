"""Genera el arte 2D de CRUNCH!: trama, cielo, viñeta, líneas de velocidad, estallido e iconos.

Uso:  python art/gen_art.py   -> escribe los PNG en art/out/
Todo se dibuja a 4x y se reduce, para que los bordes de tinta queden suaves.
"""

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).parent / "out"
OUT.mkdir(exist_ok=True)
INK = (20, 16, 16, 255)
SS = 4  # supermuestreo


def save(img: Image.Image, name: str, size):
    if isinstance(size, int):
        size = (size, size)
    img.resize(size, Image.LANCZOS).save(OUT / name)
    print("ok", name)


# ---------- Trama de puntos (baldosa repetible) ----------
def halftone():
    n = 128 * SS
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    step = n // 4
    r = step * 0.26
    for row in range(-1, 9):
        for col in range(-1, 5):
            x = col * step + (step // 2 if row % 2 else 0)
            y = row * step // 2
            d.ellipse([x - r, y - r, x + r, y + r], fill=INK)
    save(img, "halftone.png", 128)


# ---------- Cielo de cómic ----------
TOP = (52, 142, 224)
MID = (126, 206, 246)
HORIZON = (255, 240, 204)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def cloud(d, cx, cy, s):
    puffs = [(-1.5, 0.15, 0.8), (-0.7, -0.35, 1.0), (0.2, -0.55, 1.15), (1.0, -0.2, 0.95), (1.7, 0.2, 0.7), (0.1, 0.25, 1.1), (-0.8, 0.3, 0.9), (0.9, 0.3, 0.9)]
    for grow, color in ((s * 0.16, INK), (0, (255, 255, 255, 255))):
        for px, py, pr in puffs:
            r = pr * s * 0.62 + grow
            x, y = cx + px * s * 0.62, cy + py * s * 0.62
            d.ellipse([x - r, y - r, x + r, y + r], fill=color)
    # base plana del cúmulo: se recorta todo lo de abajo y se cierra con una línea de tinta
    base = cy + s * 0.45
    d.rectangle([cx - s * 2.4, base, cx + s * 2.4, base + s * 2], fill=(0, 0, 0, 0))
    d.line([(cx - s * 1.42, base - s * 0.04), (cx + s * 1.5, base - s * 0.04)], fill=INK, width=int(s * 0.16))


def sky():
    n = 1024 * 2
    side = Image.new("RGBA", (n, n), HORIZON + (255,))
    d = ImageDraw.Draw(side)
    half = n // 2
    for y in range(half):
        t = y / half
        d.line([(0, y), (n, y)], fill=lerp(TOP, MID, t) + (255,))
    # Trama: puntos del color del horizonte que crecen al bajar hasta fundirse justo en el horizonte
    step = n // 48
    start = 0.74
    for row in range(int(half * start / (step / 2)), int(half / (step / 2)) + 2):
        y = row * step // 2
        t = (y - half * start) / (half * (1 - start))
        r = step * 0.74 * max(0.0, min(1.0, t)) ** 0.8
        if r < 1:
            continue
        for col in range(-1, 50):
            x = col * step + (step // 2 if row % 2 else 0)
            d.ellipse([x - r, y - r, x + r, y + r], fill=HORIZON + (255,))
    layer = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    for cx, cy, s in ((0.18, 0.3, 105), (0.5, 0.22, 74), (0.8, 0.33, 122), (0.38, 0.4, 56), (0.64, 0.42, 48)):
        cloud(ld, cx * n, cy * n, s)
    side.alpha_composite(layer)
    save(side.convert("RGB"), "sky_side.png", 1024)
    save(Image.new("RGB", (64, 64), TOP), "sky_top.png", 64)
    save(Image.new("RGB", (64, 64), HORIZON), "sky_bottom.png", 64)


# ---------- Viñeta con trama en el borde ----------
def vignette():
    w, h = 1024, 576
    img = Image.new("RGBA", (w * 2, h * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    step = 18
    for row in range(-1, (h * 2) // (step // 2) + 2):
        for col in range(-1, (w * 2) // step + 2):
            x = col * step + (step // 2 if row % 2 else 0)
            y = row * step // 2
            nx, ny = (x / (w * 2) - 0.5) * 2, (y / (h * 2) - 0.5) * 2
            edge = max(abs(nx) ** 3 + abs(ny) ** 3, 0) ** (1 / 3)  # superelipse: esquinas de película vieja
            t = (edge - 0.8) / 0.24
            if t <= 0:
                continue
            r = step * 0.72 * min(1, t)
            d.ellipse([x - r, y - r, x + r, y + r], fill=(20, 16, 16, 150))
    save(img, "vignette.png", (w, h))


# ---------- Líneas de velocidad (manga) ----------
def speedlines():
    n = 1024 * 2
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    rnd = random.Random(3)
    c = n / 2
    a = 0.0
    while a < math.tau:
        width = rnd.uniform(0.006, 0.03)
        inner = rnd.uniform(0.52, 0.8) * c
        outer = c * 1.5
        p1 = (c + math.cos(a - width) * outer, c + math.sin(a - width) * outer)
        p2 = (c + math.cos(a + width) * outer, c + math.sin(a + width) * outer)
        tip = (c + math.cos(a) * inner, c + math.sin(a) * inner)
        d.polygon([p1, p2, tip], fill=INK)
        a += width * 2 + rnd.uniform(0.02, 0.09)
    save(img, "speedlines.png", 1024)


# ---------- Estallido de onomatopeya (blanco con tinta: se tiñe con ImageColor3) ----------
def burst():
    n = 512 * SS
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    rnd = random.Random(11)
    c = n / 2
    spikes = 13
    shape = []
    for i in range(spikes * 2):
        a = i / (spikes * 2) * math.tau + rnd.uniform(-0.05, 0.05)
        r = rnd.uniform(0.86, 1.0) if i % 2 == 0 else rnd.uniform(0.56, 0.66)
        shape.append((a, r))
    for scale, color in ((0.98, INK), (0.86, (255, 255, 255, 255))):
        d.polygon([(c + math.cos(a) * r * c * scale, c + math.sin(a) * r * c * scale) for a, r in shape], fill=color)
    save(img, "burst.png", 512)


# ---------- Iconos: siluetas de tinta ----------
def icon(name, draw_fn):
    n = 256 * SS
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    u = n / 100  # el icono se dibuja en una cuadrícula de 100x100

    def P(*pts):
        return [(x * u, y * u) for x, y in pts]

    def E(cx, cy, rx, ry=None, fill=INK):
        ry = rx if ry is None else ry
        d.ellipse([(cx - rx) * u, (cy - ry) * u, (cx + rx) * u, (cy + ry) * u], fill=fill)

    def L(pts, w=7, fill=INK):
        d.line(P(*pts), fill=fill, width=int(w * u), joint="curve")
        for x, y in pts:
            E(x, y, w / 2, fill=fill)

    def G(pts, fill=INK):
        d.polygon(P(*pts), fill=fill)

    draw_fn(E, L, G, d, u)
    save(img, f"icon_{name}.png", 256)


CLEAR = (0, 0, 0, 0)


def ant(E, L, cx=50, cy=50, s=1.0):
    E(cx, cy + 19 * s, 13 * s, 16 * s)
    E(cx, cy, 8 * s, 9 * s)
    E(cx, cy - 16 * s, 11 * s, 10 * s)
    for side in (-1, 1):
        for dy, reach in ((-6, -12), (0, 0), (6, 12)):
            L([(cx + side * 6 * s, cy + dy * s), (cx + side * 20 * s, cy + (dy + reach * 0.5) * s), (cx + side * 27 * s, cy + (dy + reach) * s)], w=3.6 * s)
        L([(cx + side * 5 * s, cy - 23 * s), (cx + side * 11 * s, cy - 34 * s), (cx + side * 18 * s, cy - 36 * s)], w=3 * s)


def i_bite(E, L, G, d, u):
    for s in (-1, 1):
        L([(50 + s * 10, 22), (50 + s * 30, 34), (50 + s * 32, 58), (50 + s * 14, 80)], w=11)
        G([(50 + s * 30, 44), (50 + s * 14, 50), (50 + s * 28, 56)])
        G([(50 + s * 27, 62), (50 + s * 12, 64), (50 + s * 22, 72)])


def i_crit(E, L, G, d, u):
    def spark(cx, cy, r):
        G([(cx, cy - r), (cx + r * 0.24, cy - r * 0.24), (cx + r, cy), (cx + r * 0.24, cy + r * 0.24), (cx, cy + r), (cx - r * 0.24, cy + r * 0.24), (cx - r, cy), (cx - r * 0.24, cy - r * 0.24)])
    spark(40, 56, 32)
    spark(74, 26, 18)


def i_saw(E, L, G, d, u):
    teeth = 12
    pts = []
    for i in range(teeth * 2):
        a = i / (teeth * 2) * math.tau
        r = 40 if i % 2 == 0 else 28
        pts.append((50 + math.cos(a + 0.2 * (i % 2)) * r, 50 + math.sin(a + 0.2 * (i % 2)) * r))
    G(pts)
    E(50, 50, 9, fill=CLEAR)


def i_area(E, L, G, d, u):
    E(50, 50, 9)
    for r, w in ((24, 7), (40, 6)):
        d.ellipse([(50 - r) * u, (50 - r) * u, (50 + r) * u, (50 + r) * u], outline=INK, width=int(w * u))


def i_speed(E, L, G, d, u):
    for x in (14, 40, 66):
        G([(x, 20), (x + 14, 20), (x + 32, 50), (x + 14, 80), (x, 80), (x + 18, 50)])


def i_carry(E, L, G, d, u):
    def crumb(x, y, s, rot):
        pts = [(-s, -s), (s, -s * 0.8), (s * 0.9, s), (-s * 0.85, s * 0.9)]
        c, sn = math.cos(rot), math.sin(rot)
        G([(x + px * c - py * sn, y + px * sn + py * c) for px, py in pts])
    crumb(31, 68, 17, 0.1)
    crumb(69, 68, 17, -0.12)
    crumb(50, 34, 17, 0.06)


def i_sprint(E, L, G, d, u):
    G([(58, 6), (22, 54), (44, 54), (36, 94), (78, 40), (54, 40)])


def i_wings(E, L, G, d, u):
    for s in (-1, 1):
        G([(50, 58), (50 + s * 14, 20), (50 + s * 42, 12), (50 + s * 46, 40), (50 + s * 30, 62)])
        G([(50, 62), (50 + s * 34, 68), (50 + s * 36, 86), (50 + s * 14, 84)])
    E(50, 60, 6, 22)


def i_nursery(E, L, G, d, u):
    E(50, 54, 30, 38)
    L([(24, 52), (36, 42), (46, 56), (56, 42), (66, 56), (76, 46)], w=5, fill=CLEAR)


def i_workers(E, L, G, d, u):
    ant(E, L, 50, 52, 1.1)


def i_workerSpeed(E, L, G, d, u):
    ant(E, L, 60, 52, 0.95)
    for y, x0 in ((30, 6), (52, 2), (74, 8)):
        L([(x0, y), (x0 + 16, y)], w=5)


def i_workerCarry(E, L, G, d, u):
    ant(E, L, 50, 62, 0.9)
    G([(34, 4), (66, 6), (64, 30), (36, 28)])


def i_barracks(E, L, G, d, u):
    G([(50, 8), (86, 20), (82, 58), (50, 92), (18, 58), (14, 20)])
    G([(50, 24), (70, 31), (68, 54), (50, 74), (32, 54), (30, 31)], fill=CLEAR)
    E(50, 46, 8)


def i_queen(E, L, G, d, u):
    G([(12, 78), (10, 30), (30, 52), (50, 18), (70, 52), (90, 30), (88, 78)])
    for x, y in ((10, 26), (50, 14), (90, 26)):
        E(x, y, 7)
    L([(22, 66), (78, 66)], w=5, fill=CLEAR)


def i_storage(E, L, G, d, u):
    d.rounded_rectangle([20 * u, 30 * u, 80 * u, 92 * u], radius=14 * u, fill=INK)
    d.rounded_rectangle([28 * u, 10 * u, 72 * u, 26 * u], radius=5 * u, fill=INK)
    E(50, 62, 14, fill=CLEAR)
    E(50, 62, 6)


def i_trail(E, L, G, d, u):
    for x, y, r in ((16, 82, 5), (32, 68, 6.5), (46, 52, 8), (60, 38, 9.5)):
        E(x, y, r)
    G([(78, 6), (94, 30), (84, 42), (70, 40), (64, 28)])
    E(78, 30, 13)


def i_frenzy(E, L, G, d, u):
    G([(50, 4), (66, 28), (62, 40), (78, 34), (86, 62), (70, 90), (30, 90), (14, 64), (26, 36), (36, 50), (38, 26)])
    G([(50, 50), (62, 70), (54, 84), (44, 84), (36, 70)], fill=CLEAR)


def i_smart(E, L, G, d, u):
    G([(4, 50), (26, 26), (50, 18), (74, 26), (96, 50), (74, 74), (50, 82), (26, 74)])
    E(50, 50, 21, fill=CLEAR)
    E(50, 50, 12)


def i_royalFood(E, L, G, d, u):
    G([(50, 6), (74, 48), (78, 62), (50, 62), (22, 62), (26, 48)])
    E(50, 62, 28)
    E(40, 66, 7, 11, fill=CLEAR)


def i_royalBite(E, L, G, d, u):
    G([(22, 14), (78, 14), (72, 52), (50, 94), (28, 52)])
    G([(36, 24), (48, 24), (44, 48)], fill=CLEAR)


def i_royalColony(E, L, G, d, u):
    for cx, cy in ((50, 28), (26, 68), (74, 68)):
        pts = [(cx + math.cos(i / 6 * math.tau + math.pi / 6) * 23, cy + math.sin(i / 6 * math.tau + math.pi / 6) * 23) for i in range(6)]
        G(pts)


def i_royalStart(E, L, G, d, u):
    d.pieslice([8 * u, 30 * u, 92 * u, 104 * u], 0, 180, fill=INK)
    for cx in (30, 50, 70):
        E(cx, 48, 11, 15)


def i_royalSpeed(E, L, G, d, u):
    for y in (14, 46):
        G([(50, y), (86, y + 28), (86, y + 42), (50, y + 16), (14, y + 42), (14, y + 28)])


def i_anthill(E, L, G, d, u):
    d.pieslice([4 * u, 26 * u, 96 * u, 150 * u], 180, 360, fill=INK)
    E(50, 44, 13, 9, fill=CLEAR)
    L([(8, 90), (92, 90)], w=6)


ICONS = {
    "bite": i_bite, "crit": i_crit, "saw": i_saw, "area": i_area,
    "speed": i_speed, "carry": i_carry, "sprint": i_sprint, "wings": i_wings,
    "nursery": i_nursery, "workers": i_workers, "workerSpeed": i_workerSpeed, "workerCarry": i_workerCarry,
    "barracks": i_barracks, "queen": i_queen, "storage": i_storage,
    "trail": i_trail, "frenzy": i_frenzy, "smart": i_smart,
    "royalFood": i_royalFood, "royalBite": i_royalBite, "royalColony": i_royalColony,
    "royalStart": i_royalStart, "royalSpeed": i_royalSpeed, "anthill": i_anthill,
}

if __name__ == "__main__":
    halftone()
    sky()
    vignette()
    speedlines()
    burst()
    for icon_name, fn in ICONS.items():
        icon(icon_name, fn)

    # Hoja de contacto para revisar los iconos de un vistazo
    names = list(ICONS)
    sheet = Image.new("RGB", (6 * 140, 4 * 140), (255, 250, 235))
    for i, icon_name in enumerate(names):
        im = Image.open(OUT / f"icon_{icon_name}.png").resize((120, 120), Image.LANCZOS)
        sheet.paste(im, (i % 6 * 140 + 10, i // 6 * 140 + 10), im)
    sheet.save(OUT / "_contact.png")
