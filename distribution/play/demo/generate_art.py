#!/usr/bin/env python3
"""Generates the artwork for the store-screenshot demo adventures.

Everything is drawn procedurally as SVG (deterministic: fixed random seeds)
and rasterised with headless Firefox, so the demo data needs no third-party
images. Output: distribution/play/demo/build/art/<name>.png (gitignored).

Usage: distribution/play/demo/generate_art.py [name ...]   # all, or only the named images
"""
import math
import os
import random
import subprocess
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "build", "art")
TITLE_FONT = "Instrument Serif, Liberation Serif, serif"


# --- building blocks ------------------------------------------------------

def sky(w, h, top, bottom, gid="sky"):
    return (f'<defs><linearGradient id="{gid}" x1="0" y1="0" x2="0" y2="1">'
            f'<stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/>'
            f'</linearGradient></defs><rect width="{w}" height="{h}" fill="url(#{gid})"/>')


def stars(w, h, n, rnd, max_y=0.6):
    out = []
    for _ in range(n):
        x, y = rnd.uniform(0, w), rnd.uniform(0, h * max_y)
        r = rnd.choice([0.6, 0.8, 1.0, 1.3, 1.8])
        o = rnd.uniform(0.35, 0.95)
        out.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r}" fill="#fff" opacity="{o:.2f}"/>')
    return "".join(out)


def moon(cx, cy, r, color="#f3ead2", gid="moonglow"):
    return (f'<defs><radialGradient id="{gid}"><stop offset="0" stop-color="{color}" stop-opacity="0.55"/>'
            f'<stop offset="1" stop-color="{color}" stop-opacity="0"/></radialGradient></defs>'
            f'<circle cx="{cx}" cy="{cy}" r="{r * 4}" fill="url(#{gid})"/>'
            f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{color}"/>')


def ridge(w, h, base, rough, color, rnd, step=None, opacity=1.0):
    """A jagged silhouette band from y=base (fraction of h) down to the bottom."""
    step = step or w / 40
    y = h * base
    pts = [(0, h), (0, y)]
    x = 0.0
    while x < w:
        x += step * rnd.uniform(0.6, 1.4)
        y += rnd.uniform(-rough, rough)
        y = max(h * (base - 0.18), min(h * (base + 0.12), y))
        pts.append((min(x, w), y))
    pts += [(w, h)]
    d = " ".join(f"{px:.1f},{py:.1f}" for px, py in pts)
    return f'<polygon points="{d}" fill="{color}" opacity="{opacity}"/>'


def sea(w, h, top, c1, c2, rnd, gid="sea"):
    out = [f'<defs><linearGradient id="{gid}" x1="0" y1="0" x2="0" y2="1">'
           f'<stop offset="0" stop-color="{c1}"/><stop offset="1" stop-color="{c2}"/></linearGradient></defs>',
           f'<rect x="0" y="{h * top:.1f}" width="{w}" height="{h * (1 - top):.1f}" fill="url(#{gid})"/>']
    for i in range(70):
        y = h * top + (i / 70) ** 1.6 * h * (1 - top)
        x = rnd.uniform(-50, w)
        ln = rnd.uniform(w * 0.03, w * 0.18) * (0.4 + i / 70)
        out.append(f'<line x1="{x:.0f}" y1="{y:.0f}" x2="{x + ln:.0f}" y2="{y:.0f}" '
                   f'stroke="#cfe3e6" stroke-width="{0.6 + i / 40:.1f}" opacity="{rnd.uniform(0.08, 0.25):.2f}"/>')
    return "".join(out)


def moon_path(w, h, cx, top, color="#f3ead2"):
    """A shimmering reflection column on the water under the moon."""
    out = []
    rnd = random.Random(7)
    for i in range(40):
        y = h * top + i * (h * (1 - top) / 40)
        half = 8 + i * 2.2
        x = cx + rnd.uniform(-10, 10)
        out.append(f'<line x1="{x - half:.0f}" y1="{y:.0f}" x2="{x + half:.0f}" y2="{y:.0f}" '
                   f'stroke="{color}" stroke-width="2" opacity="{0.45 - i * 0.009:.2f}"/>')
    return "".join(out)


def lighthouse(x, base_y, height, beam=True, color="#0b1418"):
    wb, wt = height * 0.16, height * 0.09
    top = base_y - height
    out = []
    if beam:
        out.append('<defs><linearGradient id="beam" x1="0" y1="0" x2="1" y2="0">'
                   '<stop offset="0" stop-color="#ffe7a8" stop-opacity="0.75"/>'
                   '<stop offset="1" stop-color="#ffe7a8" stop-opacity="0"/></linearGradient></defs>')
        out.append(f'<polygon points="{x},{top + 10} {x + height * 2.6},{top - height * 0.35} '
                   f'{x + height * 2.6},{top + height * 0.25}" fill="url(#beam)"/>')
    out.append(f'<polygon points="{x - wb / 2},{base_y} {x + wb / 2},{base_y} {x + wt / 2},{top + 22} '
               f'{x - wt / 2},{top + 22}" fill="{color}"/>')
    out.append(f'<rect x="{x - wt * 0.7}" y="{top + 8}" width="{wt * 1.4}" height="16" fill="{color}"/>')
    out.append(f'<rect x="{x - wt * 0.45}" y="{top - 14}" width="{wt * 0.9}" height="22" fill="#ffd77a"/>')
    out.append(f'<polygon points="{x - wt * 0.6},{top - 14} {x + wt * 0.6},{top - 14} {x},{top - 34}" fill="{color}"/>')
    return "".join(out)


def pines(w, h, base, count, color, rnd, size=(60, 160)):
    out = []
    for _ in range(count):
        x = rnd.uniform(-20, w + 20)
        s = rnd.uniform(*size)
        y = h * base + rnd.uniform(-10, 30)
        for k in range(4):
            tw = s * (0.55 - k * 0.11)
            ty = y - k * s * 0.22
            out.append(f'<polygon points="{x - tw},{ty} {x + tw},{ty} {x},{ty - s * 0.42}" fill="{color}"/>')
        out.append(f'<rect x="{x - s * 0.04}" y="{y}" width="{s * 0.08}" height="{s * 0.2}" fill="{color}"/>')
    return "".join(out)


def castle(x, base_y, scale, color):
    s = scale
    out = [f'<rect x="{x - 160 * s}" y="{base_y - 120 * s}" width="{320 * s}" height="{120 * s}" fill="{color}"/>']
    for tx, th in ((-170, 230), (170, 210), (-60, 300), (70, 260)):
        cx = x + tx * s
        out.append(f'<rect x="{cx - 28 * s}" y="{base_y - th * s}" width="{56 * s}" height="{th * s}" fill="{color}"/>')
        out.append(f'<polygon points="{cx - 36 * s},{base_y - th * s} {cx + 36 * s},{base_y - th * s} '
                   f'{cx},{base_y - (th + 70) * s}" fill="{color}"/>')
        out.append(f'<rect x="{cx - 5 * s}" y="{base_y - (th - 40) * s}" width="{10 * s}" height="{18 * s}" fill="#ffb347" opacity="0.85"/>')
    for i in range(9):
        out.append(f'<rect x="{x - 160 * s + i * 38 * s}" y="{base_y - 136 * s}" width="{22 * s}" height="{16 * s}" fill="{color}"/>')
    return "".join(out)


def fog(w, h, y, color, rnd, n=14, opacity=0.18):
    out = ['<defs><filter id="blur" x="-20%" y="-50%" width="140%" height="200%">'
           '<feGaussianBlur stdDeviation="30"/></filter></defs>']
    for _ in range(n):
        out.append(f'<ellipse cx="{rnd.uniform(0, w):.0f}" cy="{h * y + rnd.uniform(-40, 40):.0f}" '
                   f'rx="{rnd.uniform(w * 0.1, w * 0.3):.0f}" ry="{rnd.uniform(25, 70):.0f}" '
                   f'fill="{color}" opacity="{opacity}" filter="url(#blur)"/>')
    return "".join(out)


def vignette(w, h, strength=0.6):
    return ('<defs><radialGradient id="vig" cx="0.5" cy="0.5" r="0.75">'
            '<stop offset="0.55" stop-color="#000" stop-opacity="0"/>'
            f'<stop offset="1" stop-color="#000" stop-opacity="{strength}"/></radialGradient></defs>'
            f'<rect width="{w}" height="{h}" fill="url(#vig)"/>')


def svg(w, h, body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{body}</svg>'


# --- scenes ---------------------------------------------------------------

def harbour(w, h, seed=1, moon_y=0.2):
    r = random.Random(seed)
    b = [sky(w, h, "#0d1b2e", "#3b4f6b"), stars(w, h, 160, r), moon(w * 0.72, h * moon_y, h * 0.05)]
    b.append(ridge(w, h, 0.56, 22, "#17263a", r))
    b.append(lighthouse(w * 0.18, h * 0.6, h * 0.34))
    b.append(sea(w, h, 0.6, "#1d3550", "#0a1522", r))
    b.append(moon_path(w, h, w * 0.72, 0.6))
    # harbour houses with lit windows
    for i in range(14):
        x = w * 0.42 + i * w * 0.04
        hh = r.uniform(h * 0.08, h * 0.15)
        b.append(f'<rect x="{x:.0f}" y="{h * 0.6 - hh:.0f}" width="{w * 0.036:.0f}" height="{hh:.0f}" fill="#0e1824"/>')
        b.append(f'<polygon points="{x - 4:.0f},{h * 0.6 - hh:.0f} {x + w * 0.036 + 4:.0f},{h * 0.6 - hh:.0f} '
                 f'{x + w * 0.018:.0f},{h * 0.6 - hh - 30:.0f}" fill="#0e1824"/>')
        if r.random() < 0.7:
            b.append(f'<rect x="{x + 10:.0f}" y="{h * 0.6 - hh + 20:.0f}" width="12" height="16" fill="#ffc96b" opacity="0.9"/>')
    b.append(fog(w, h, 0.6, "#9fb3c8", r))
    b.append(vignette(w, h))
    return svg(w, h, "".join(b))


def inn(w, h, seed=2):
    r = random.Random(seed)
    b = [f'<defs><radialGradient id="fire" cx="0.3" cy="0.75" r="0.8"><stop offset="0" stop-color="#ffb05c"/>'
         f'<stop offset="0.45" stop-color="#7a3a17"/><stop offset="1" stop-color="#1b0f0a"/></radialGradient></defs>'
         f'<rect width="{w}" height="{h}" fill="url(#fire)"/>']
    for i in range(9):  # wooden beams
        b.append(f'<rect x="{i * w / 8 - 20:.0f}" y="0" width="34" height="{h}" fill="#1f120b" opacity="0.55"/>')
    b.append(f'<rect x="0" y="{h * 0.12:.0f}" width="{w}" height="30" fill="#1f120b" opacity="0.7"/>')
    b.append(f'<rect x="{w * 0.08:.0f}" y="{h * 0.5:.0f}" width="{w * 0.34:.0f}" height="{h * 0.5:.0f}" fill="#120a06"/>')
    b.append(f'<ellipse cx="{w * 0.25:.0f}" cy="{h * 0.8:.0f}" rx="{w * 0.12:.0f}" ry="{h * 0.1:.0f}" fill="#ff8a2a" opacity="0.8"/>')
    for i in range(6):  # tables and mugs
        x = w * 0.5 + i * w * 0.08
        b.append(f'<rect x="{x:.0f}" y="{h * 0.72:.0f}" width="{w * 0.06:.0f}" height="14" fill="#140b07"/>')
        b.append(f'<rect x="{x + 20:.0f}" y="{h * 0.72 - 26:.0f}" width="16" height="26" fill="#140b07"/>')
    b.append(fog(w, h, 0.3, "#ffcf99", r, n=8, opacity=0.12))
    b.append(vignette(w, h, 0.75))
    return svg(w, h, "".join(b))


def chapel(w, h, seed=3):
    r = random.Random(seed)
    b = [sky(w, h, "#1a1630", "#5a4a6e"), stars(w, h, 90, r), moon(w * 0.25, h * 0.18, h * 0.04, "#e9e2ff")]
    b.append(ridge(w, h, 0.62, 18, "#141022", r))
    cx, base = w * 0.62, h * 0.62
    b.append(f'<rect x="{cx - 150:.0f}" y="{base - 160:.0f}" width="300" height="160" fill="#0d0a18"/>')
    b.append(f'<polygon points="{cx - 170:.0f},{base - 160:.0f} {cx + 170:.0f},{base - 160:.0f} {cx:.0f},{base - 280:.0f}" fill="#0d0a18"/>')
    b.append(f'<rect x="{cx + 90:.0f}" y="{base - 330:.0f}" width="60" height="330" fill="#0d0a18"/>')
    b.append(f'<polygon points="{cx + 80:.0f},{base - 330:.0f} {cx + 160:.0f},{base - 330:.0f} {cx + 120:.0f},{base - 430:.0f}" fill="#0d0a18"/>')
    b.append(f'<path d="M{cx - 30:.0f},{base - 40:.0f} v-60 a30,30 0 0 1 60,0 v60 z" fill="#b9a6ff" opacity="0.55"/>')
    for i in range(18):  # gravestones
        x = r.uniform(w * 0.05, w * 0.95)
        y = base + r.uniform(10, h * 0.3)
        s = 0.5 + (y - base) / h
        b.append(f'<path d="M{x:.0f},{y:.0f} v{-40 * s:.0f} a{14 * s:.0f},{14 * s:.0f} 0 0 1 {28 * s:.0f},0 v{40 * s:.0f} z" fill="#0b0814"/>')
    b.append(fog(w, h, 0.7, "#cbbcf0", r, opacity=0.2))
    b.append(vignette(w, h))
    return svg(w, h, "".join(b))


def cove(w, h, seed=4):
    r = random.Random(seed)
    b = [sky(w, h, "#0b1622", "#24384a"), stars(w, h, 120, r)]
    b.append(sea(w, h, 0.58, "#183247", "#071017", r))
    b.append(ridge(w, h, 0.35, 30, "#0a1118", r, step=w / 25))
    b.append(f'<rect x="0" y="0" width="{w * 0.12:.0f}" height="{h}" fill="#070c11"/>')
    b.append(f'<rect x="{w * 0.88:.0f}" y="0" width="{w * 0.12:.0f}" height="{h}" fill="#070c11"/>')
    b.append(f'<path d="M{w * 0.42:.0f},{h * 0.66:.0f} q{w * 0.08:.0f},{h * 0.07:.0f} {w * 0.16:.0f},0 l-20,-40 '
             f'h-{w * 0.12:.0f} z" fill="#05090d"/>')  # boat
    b.append(f'<line x1="{w * 0.5:.0f}" y1="{h * 0.6:.0f}" x2="{w * 0.5:.0f}" y2="{h * 0.35:.0f}" stroke="#05090d" stroke-width="6"/>')
    for i in range(3):  # lanterns
        x = w * (0.3 + i * 0.2)
        b.append(f'<circle cx="{x:.0f}" cy="{h * 0.7:.0f}" r="40" fill="#ffb347" opacity="0.18"/>')
        b.append(f'<circle cx="{x:.0f}" cy="{h * 0.7:.0f}" r="7" fill="#ffd27a"/>')
    b.append(fog(w, h, 0.62, "#8ba3b8", r))
    b.append(vignette(w, h, 0.7))
    return svg(w, h, "".join(b))


def caves(w, h, seed=5):
    r = random.Random(seed)
    b = [f'<defs><radialGradient id="cave" cx="0.5" cy="0.55" r="0.7"><stop offset="0" stop-color="#2d6b6f"/>'
         f'<stop offset="0.5" stop-color="#123033"/><stop offset="1" stop-color="#040a0b"/></radialGradient></defs>'
         f'<rect width="{w}" height="{h}" fill="url(#cave)"/>']
    for i in range(26):  # stalactites
        x = r.uniform(0, w)
        ln = r.uniform(h * 0.08, h * 0.32)
        b.append(f'<polygon points="{x - 30:.0f},0 {x + 30:.0f},0 {x:.0f},{ln:.0f}" fill="#061112"/>')
    b.append(ridge(w, h, 0.8, 18, "#051011", r))
    for i in range(30):  # glowing water spots
        b.append(f'<circle cx="{r.uniform(0, w):.0f}" cy="{r.uniform(h * 0.6, h * 0.85):.0f}" r="{r.uniform(2, 5):.1f}" '
                 f'fill="#7ff4e6" opacity="{r.uniform(0.3, 0.8):.2f}"/>')
    b.append(fog(w, h, 0.65, "#5fd0c4", r, opacity=0.12))
    b.append(vignette(w, h, 0.8))
    return svg(w, h, "".join(b))


def market(w, h, seed=6):
    r = random.Random(seed)
    b = [sky(w, h, "#120d22", "#3c2142"), stars(w, h, 60, r, 0.35)]
    for i in range(7):  # stalls
        x = w * 0.04 + i * w * 0.14
        col = r.choice(["#7b2d2d", "#2d5a7b", "#6b5a1f", "#3f6b3a"])
        b.append(f'<rect x="{x:.0f}" y="{h * 0.55:.0f}" width="{w * 0.12:.0f}" height="{h * 0.3:.0f}" fill="#120b14"/>')
        b.append(f'<polygon points="{x - 10:.0f},{h * 0.55:.0f} {x + w * 0.12 + 10:.0f},{h * 0.55:.0f} '
                 f'{x + w * 0.1:.0f},{h * 0.45:.0f} {x + w * 0.02:.0f},{h * 0.45:.0f}" fill="{col}"/>')
    for i in range(40):  # string lights
        x = i * w / 39
        y = h * 0.3 + 30 * math.sin(i / 39 * math.pi * 3)
        b.append(f'<circle cx="{x:.0f}" cy="{y:.0f}" r="16" fill="#ffcc66" opacity="0.15"/>')
        b.append(f'<circle cx="{x:.0f}" cy="{y:.0f}" r="4" fill="#ffe2a0"/>')
    b.append(f'<rect x="0" y="{h * 0.85:.0f}" width="{w}" height="{h * 0.15:.0f}" fill="#0b070d"/>')
    b.append(vignette(w, h))
    return svg(w, h, "".join(b))


def stair(w, h, seed=8):
    r = random.Random(seed)
    b = [f'<defs><radialGradient id="tower" cx="0.5" cy="0.15" r="0.9"><stop offset="0" stop-color="#ffe2a6"/>'
         f'<stop offset="0.3" stop-color="#6e5a3c"/><stop offset="1" stop-color="#120f0b"/></radialGradient></defs>'
         f'<rect width="{w}" height="{h}" fill="url(#tower)"/>']
    for i in range(16):  # spiral steps
        a = i / 16 * math.pi * 2.2
        x = w * 0.5 + math.cos(a) * w * 0.28
        y = h * 0.95 - i * h * 0.055
        b.append(f'<rect x="{x - 90:.0f}" y="{y:.0f}" width="180" height="22" fill="#17120c" opacity="{0.6 + i / 40:.2f}"/>')
    b.append(f'<rect x="{w * 0.49:.0f}" y="0" width="{w * 0.02:.0f}" height="{h}" fill="#17120c"/>')
    b.append(vignette(w, h, 0.7))
    return svg(w, h, "".join(b))


def choir(w, h, seed=9):
    r = random.Random(seed)
    b = [f'<defs><linearGradient id="deep" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2a8a8f"/>'
         f'<stop offset="1" stop-color="#04131a"/></linearGradient></defs><rect width="{w}" height="{h}" fill="url(#deep)"/>']
    for i in range(8):  # light shafts
        x = r.uniform(0, w)
        b.append(f'<polygon points="{x:.0f},0 {x + 60:.0f},0 {x + 260:.0f},{h} {x + 120:.0f},{h}" fill="#bff7f0" opacity="0.07"/>')
    for i in range(7):  # drowned figures
        x = w * 0.15 + i * w * 0.115
        y = h * 0.62 + r.uniform(-20, 20)
        b.append(f'<circle cx="{x:.0f}" cy="{y - 90:.0f}" r="26" fill="#03151a" opacity="0.85"/>')
        b.append(f'<path d="M{x - 45:.0f},{y + 140:.0f} q0,-170 45,-200 q45,30 45,200 z" fill="#03151a" opacity="0.85"/>')
    for i in range(70):  # bubbles
        b.append(f'<circle cx="{r.uniform(0, w):.0f}" cy="{r.uniform(0, h):.0f}" r="{r.uniform(2, 7):.1f}" '
                 f'fill="none" stroke="#c9fff6" stroke-width="1.2" opacity="{r.uniform(0.2, 0.6):.2f}"/>')
    b.append(vignette(w, h, 0.75))
    return svg(w, h, "".join(b))


def dawn(w, h, seed=10):
    r = random.Random(seed)
    b = [sky(w, h, "#2c3e63", "#f2b26b"), f'<circle cx="{w * 0.5:.0f}" cy="{h * 0.62:.0f}" r="{h * 0.1:.0f}" fill="#ffd89a"/>']
    b.append(sea(w, h, 0.62, "#c98a5a", "#2b3a55", r))
    b.append(moon_path(w, h, w * 0.5, 0.62, "#ffe2b0"))
    b.append(ridge(w, h, 0.6, 16, "#3b3346", r))
    b.append(lighthouse(w * 0.8, h * 0.62, h * 0.32, beam=False, color="#2a2433"))
    b.append(vignette(w, h, 0.4))
    return svg(w, h, "".join(b))


def map_image(w, h, seed=11):
    r = random.Random(seed)
    b = [f'<rect width="{w}" height="{h}" fill="#e8dcc4"/>']
    pts = []
    for i in range(60):
        a = i / 60 * math.pi * 2
        rr = h * 0.33 * (1 + 0.18 * math.sin(a * 3 + 1) + r.uniform(-0.05, 0.05))
        pts.append(f"{w * 0.45 + math.cos(a) * rr * 1.3:.0f},{h * 0.5 + math.sin(a) * rr:.0f}")
    b.append(f'<polygon points="{" ".join(pts)}" fill="#cbb98f" stroke="#6b5532" stroke-width="4"/>')
    for i in range(6):
        b.append(f'<circle cx="{r.uniform(w * 0.3, w * 0.6):.0f}" cy="{r.uniform(h * 0.3, h * 0.7):.0f}" r="9" fill="#7a2d22"/>')
    b.append(f'<path d="M{w * 0.3:.0f},{h * 0.4:.0f} C{w * 0.45:.0f},{h * 0.2:.0f} {w * 0.55:.0f},{h * 0.8:.0f} {w * 0.62:.0f},{h * 0.55:.0f}" '
             f'stroke="#7a2d22" stroke-width="4" stroke-dasharray="14 10" fill="none"/>')
    b.append(f'<text x="{w * 0.08:.0f}" y="{h * 0.12:.0f}" font-family="{TITLE_FONT}" font-size="{h * 0.07:.0f}" fill="#4a3920">Greywater Isle</text>')
    b.append(f'<g transform="translate({w * 0.86:.0f},{h * 0.8:.0f})"><circle r="60" fill="none" stroke="#4a3920" stroke-width="3"/>'
             f'<polygon points="0,-70 12,0 0,70 -12,0" fill="#4a3920"/></g>')
    return svg(w, h, "".join(b))


# --- portraits ------------------------------------------------------------

def portrait(w, h, bg1, bg2, rim, figure, seed):
    """A head-and-shoulders silhouette with a rim light on a painted backdrop."""
    r = random.Random(seed)
    b = [f'<defs><radialGradient id="pbg" cx="0.5" cy="0.35" r="0.85"><stop offset="0" stop-color="{bg1}"/>'
         f'<stop offset="1" stop-color="{bg2}"/></radialGradient>'
         f'<filter id="rim" x="-10%" y="-10%" width="120%" height="120%"><feGaussianBlur stdDeviation="9"/></filter></defs>'
         f'<rect width="{w}" height="{h}" fill="url(#pbg)"/>']
    for _ in range(40):
        b.append(f'<circle cx="{r.uniform(0, w):.0f}" cy="{r.uniform(0, h):.0f}" r="{r.uniform(20, 90):.0f}" '
                 f'fill="#fff" opacity="{r.uniform(0.01, 0.04):.3f}"/>')
    cx, head_y, hr = w * 0.5, h * 0.4, w * 0.17
    shoulders = (f'M{cx - w * 0.46:.0f},{h} C{cx - w * 0.44:.0f},{h * 0.7:.0f} {cx - w * 0.2:.0f},{h * 0.6:.0f} '
                 f'{cx:.0f},{h * 0.6:.0f} C{cx + w * 0.2:.0f},{h * 0.6:.0f} {cx + w * 0.44:.0f},{h * 0.7:.0f} {cx + w * 0.46:.0f},{h} Z')
    parts = [f'<path d="{shoulders}"/>', f'<rect x="{cx - hr * 0.45:.0f}" y="{head_y:.0f}" width="{hr * 0.9:.0f}" height="{h * 0.2:.0f}"/>',
             f'<ellipse cx="{cx:.0f}" cy="{head_y:.0f}" rx="{hr * 0.85:.0f}" ry="{hr:.0f}"/>']
    if figure == "hood":
        parts.append(f'<path d="M{cx - hr * 1.35:.0f},{head_y + hr * 1.6:.0f} Q{cx - hr * 1.4:.0f},{head_y - hr * 1.7:.0f} '
                     f'{cx:.0f},{head_y - hr * 1.45:.0f} Q{cx + hr * 1.4:.0f},{head_y - hr * 1.7:.0f} {cx + hr * 1.35:.0f},{head_y + hr * 1.6:.0f} Z"/>')
    elif figure == "hat":
        parts.append(f'<ellipse cx="{cx:.0f}" cy="{head_y - hr * 0.55:.0f}" rx="{hr * 1.8:.0f}" ry="{hr * 0.28:.0f}"/>')
        parts.append(f'<path d="M{cx - hr * 0.9:.0f},{head_y - hr * 0.55:.0f} L{cx - hr * 0.7:.0f},{head_y - hr * 1.6:.0f} '
                     f'L{cx + hr * 0.7:.0f},{head_y - hr * 1.6:.0f} L{cx + hr * 0.9:.0f},{head_y - hr * 0.55:.0f} Z"/>')
    elif figure == "long_hair":
        parts.append(f'<path d="M{cx - hr * 1.0:.0f},{head_y:.0f} Q{cx - hr * 1.3:.0f},{head_y + hr * 2.2:.0f} '
                     f'{cx - hr * 0.3:.0f},{head_y + hr * 2.3:.0f} L{cx + hr * 0.3:.0f},{head_y + hr * 2.3:.0f} '
                     f'Q{cx + hr * 1.3:.0f},{head_y + hr * 2.2:.0f} {cx + hr * 1.0:.0f},{head_y:.0f} '
                     f'Q{cx:.0f},{head_y - hr * 1.4:.0f} {cx - hr * 1.0:.0f},{head_y:.0f} Z"/>')
    elif figure == "veil":
        parts.append(f'<path d="M{cx - hr * 1.1:.0f},{head_y - hr * 0.6:.0f} Q{cx:.0f},{head_y - hr * 1.6:.0f} '
                     f'{cx + hr * 1.1:.0f},{head_y - hr * 0.6:.0f} L{cx + w * 0.42:.0f},{h} L{cx - w * 0.42:.0f},{h} Z" opacity="0.8"/>')
    elif figure == "cap":
        parts.append(f'<path d="M{cx - hr * 0.95:.0f},{head_y - hr * 0.3:.0f} Q{cx:.0f},{head_y - hr * 1.5:.0f} '
                     f'{cx + hr * 0.95:.0f},{head_y - hr * 0.3:.0f} L{cx + hr * 1.5:.0f},{head_y - hr * 0.1:.0f} '
                     f'L{cx - hr * 0.95:.0f},{head_y - hr * 0.1:.0f} Z"/>')
    body = "".join(parts)
    b.append(f'<g fill="{rim}" filter="url(#rim)" transform="translate(6,-4)">{body}</g>')
    b.append(f'<g fill="#07090b">{body}</g>')
    b.append(vignette(w, h, 0.55))
    return svg(w, h, "".join(b))


# --- covers ---------------------------------------------------------------

def cover(w, h, art_fn, title, subtitle, seed):
    inner = art_fn(w, h, seed)
    body = inner[inner.index(">") + 1:inner.rindex("</svg>")]
    lines = title.split("\n")
    size = w * 0.115
    text = []
    for i, line in enumerate(lines):
        text.append(f'<text x="{w / 2:.0f}" y="{h * 0.14 + i * size * 1.05:.0f}" text-anchor="middle" '
                    f'font-family="{TITLE_FONT}" font-size="{size:.0f}" fill="#f3ead2" '
                    f'style="paint-order:stroke" stroke="#000" stroke-opacity="0.35" stroke-width="6">{line}</text>')
    text.append(f'<text x="{w / 2:.0f}" y="{h * 0.93:.0f}" text-anchor="middle" font-family="{TITLE_FONT}" '
                f'font-size="{w * 0.045:.0f}" font-style="italic" fill="#e8dcc4" opacity="0.9">{subtitle}</text>')
    shade = (f'<defs><linearGradient id="shade" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#000" stop-opacity="0.55"/>'
             f'<stop offset="0.35" stop-color="#000" stop-opacity="0"/><stop offset="0.8" stop-color="#000" stop-opacity="0"/>'
             f'<stop offset="1" stop-color="#000" stop-opacity="0.6"/></linearGradient></defs>'
             f'<rect width="{w}" height="{h}" fill="url(#shade)"/>')
    return svg(w, h, body + shade + "".join(text))


def forest(w, h, seed=12):
    r = random.Random(seed)
    b = [sky(w, h, "#0e1f17", "#4d6b4a"), moon(w * 0.5, h * 0.42, w * 0.07, "#e8f0d0")]
    b.append(pines(w, h, 0.62, 14, "#16261c", r, (w * 0.12, w * 0.3)))
    b.append(fog(w, h, 0.68, "#c8dcc0", r, opacity=0.22))
    b.append(pines(w, h, 0.85, 10, "#07100b", r, (w * 0.2, w * 0.45)))
    b.append(vignette(w, h, 0.7))
    return svg(w, h, "".join(b))


def crown(w, h, seed=13):
    r = random.Random(seed)
    b = [sky(w, h, "#2a0d0d", "#c2512a"), stars(w, h, 30, r, 0.3)]
    b.append(ridge(w, h, 0.7, 26, "#3a1410", r))
    b.append(castle(w * 0.5, h * 0.68, w / 900, "#1a0806"))
    for _ in range(80):  # embers
        b.append(f'<circle cx="{r.uniform(0, w):.0f}" cy="{r.uniform(h * 0.2, h):.0f}" r="{r.uniform(1, 3.5):.1f}" '
                 f'fill="#ffb347" opacity="{r.uniform(0.3, 0.9):.2f}"/>')
    b.append(ridge(w, h, 0.86, 14, "#0f0403", r))
    b.append(vignette(w, h, 0.6))
    return svg(w, h, "".join(b))


# --- rendering ------------------------------------------------------------

ART = {
    # scene backgrounds (16:9)
    "bg_harbour": lambda: harbour(1600, 900),
    "bg_inn": lambda: inn(1600, 900),
    "bg_chapel": lambda: chapel(1600, 900),
    "bg_cove": lambda: cove(1600, 900),
    "bg_caves": lambda: caves(1600, 900),
    "bg_market": lambda: market(1600, 900),
    "bg_stair": lambda: stair(1600, 900),
    "bg_choir": lambda: choir(1600, 900),
    "bg_dawn": lambda: dawn(1600, 900),
    "bg_castle": lambda: crown(1600, 900),
    "bg_forest": lambda: forest(1600, 900),
    # scene image
    "img_map": lambda: map_image(1600, 1000),
    # NPC portraits (cover profile 1:1.43)
    "npc_maren": lambda: portrait(1000, 1430, "#5c7a91", "#1b2733", "#ffd28a", "long_hair", 21),
    "npc_ilse": lambda: portrait(1000, 1430, "#7a4a36", "#1f1310", "#ffb070", "hat", 22),
    "npc_aldous": lambda: portrait(1000, 1430, "#5d5478", "#18151f", "#d8ccff", "hood", 23),
    "npc_quill": lambda: portrait(1000, 1430, "#6b6b4a", "#1c1c12", "#f0e6a0", "cap", 24),
    "npc_bride": lambda: portrait(1000, 1430, "#3f8f8c", "#06191c", "#b8fff4", "veil", 25),
    # covers (1000x1430)
    "cover_lantern": lambda: cover(1000, 1430, lambda w, h, seed: harbour(w, h, seed, moon_y=0.4),
                                   "The Sunken\nLantern", "A coastal mystery", 31),
    "cover_crown": lambda: cover(1000, 1430, crown, "Ashes of the\nIron Crown", "A tale of fire and fealty", 32),
    "cover_pines": lambda: cover(1000, 1430, forest, "Whispers in\nthe Pines", "A woodland horror", 33),
}


def render(name, svg_text):
    svg_path = os.path.join(OUT, f"{name}.svg")
    png_path = os.path.join(OUT, f"{name}.png")
    with open(svg_path, "w", encoding="utf-8") as f:
        f.write(svg_text)
    w = int(svg_text.split('width="', 1)[1].split('"', 1)[0])
    h = int(svg_text.split('height="', 1)[1].split('"', 1)[0])
    html = os.path.join(OUT, f"{name}.html")
    with open(html, "w", encoding="utf-8") as f:
        f.write(f'<html><body style="margin:0;overflow:hidden"><img src="{name}.svg" '
                f'width="{w}" height="{h}" style="display:block"></body></html>')
    # Headless Firefox occasionally hangs on start-up: use a fresh profile per
    # image, a short timeout and a couple of retries.
    for attempt in range(3):
        with tempfile.TemporaryDirectory() as profile:
            try:
                subprocess.run(["firefox", "--headless", "--no-remote", "--profile", profile,
                                f"--window-size={w},{h}", "--screenshot", png_path, f"file://{html}"],
                               check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=45)
                break
            except subprocess.TimeoutExpired:
                print(f"  {name}: firefox timed out (attempt {attempt + 1})", flush=True)
    else:
        raise RuntimeError(f"could not render {name}")
    from PIL import Image
    Image.open(png_path).convert("RGB").save(png_path)
    os.remove(html)
    print(f"{name}.png {w}x{h}", flush=True)


def main(names):
    os.makedirs(OUT, exist_ok=True)
    for name, fn in ART.items():
        if not names or name in names:
            render(name, fn())


if __name__ == "__main__":
    import sys
    main(sys.argv[1:])
