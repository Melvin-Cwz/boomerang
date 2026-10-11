#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 MelvinCwz
"""Draw the conversation backgrounds offered in Personnaliser › Fond
(data/backgrounds/*.svg). Soft, low-contrast pictures: a light veil is laid
over them in the app, so bubbles stay readable. Run from the repository root."""

import math
import os
import random

W, H = 1200, 900
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "backgrounds")


def svg(name, body, defs=""):
    with open(os.path.join(OUT, name + ".svg"), "w") as f:
        f.write(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">'
                f"<defs>{defs}</defs>{body}</svg>\n")


def bulles():
    r = random.Random(3)
    body = '<rect width="100%" height="100%" fill="#f6eef7"/>'
    colours = ["#e2b8de", "#cfa0d8", "#f0c9e0", "#d9c2f0", "#f5d6e8"]
    for _ in range(46):
        x, y, s = r.uniform(-60, W + 60), r.uniform(-60, H + 60), r.uniform(18, 120)
        body += f'<circle cx="{x:.0f}" cy="{y:.0f}" r="{s:.0f}" fill="{r.choice(colours)}" opacity="{r.uniform(0.35, 0.7):.2f}"/>'
    svg("bulles", body)


def vagues():
    body = '<rect width="100%" height="100%" fill="#e8f4f8"/>'
    colours = ["#bfe3ee", "#9fd3e3", "#7fc2d8", "#64afcc", "#4f9cbf"]
    for i, colour in enumerate(colours):
        base = 260 + i * 140
        d = f"M0 {base}"
        for x in range(0, W + 1, 40):
            y = base + 38 * math.sin(x / 170 + i * 1.3) + 18 * math.sin(x / 61 + i)
            d += f" L{x} {y:.1f}"
        d += f" L{W} {H} L0 {H} Z"
        body += f'<path d="{d}" fill="{colour}" opacity="0.75"/>'
    svg("vagues", body)


def confettis():
    r = random.Random(7)
    body = '<rect width="100%" height="100%" fill="#fbf7ef"/>'
    colours = ["#ed5353", "#ffa154", "#f9c440", "#68b723", "#28bca3", "#3689e6", "#a56de2", "#de3e80"]
    for _ in range(170):
        x, y, a = r.uniform(0, W), r.uniform(0, H), r.uniform(0, 180)
        body += (f'<rect x="{x:.0f}" y="{y:.0f}" width="22" height="7" rx="3.5" fill="{r.choice(colours)}" '
                 f'opacity="0.45" transform="rotate({a:.0f} {x + 11:.0f} {y + 3.5:.0f})"/>')
    svg("confettis", body)


def pois():
    body = '<rect width="100%" height="100%" fill="#fdf1e6"/>'
    for row in range(0, H // 50 + 2):
        for col in range(0, W // 50 + 2):
            x = col * 50 + (25 if row % 2 else 0)
            body += f'<circle cx="{x}" cy="{row * 50}" r="7" fill="#f4b78a" opacity="0.6"/>'
    svg("pois", body)


def collines():
    defs = ('<linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">'
            '<stop offset="0" stop-color="#ffd8b5"/><stop offset="1" stop-color="#f7b9c4"/></linearGradient>')
    body = '<rect width="100%" height="100%" fill="url(#sky)"/>'
    body += '<circle cx="860" cy="300" r="90" fill="#fff2d6" opacity="0.9"/>'
    for i, colour in enumerate(["#e7a2b8", "#c98aa8", "#a97597", "#876283"]):
        base = 470 + i * 110
        d = f"M0 {base}"
        for x in range(0, W + 1, 30):
            y = base - 70 * math.sin(x / (260 + 40 * i) + i * 2.1) ** 2
            d += f" L{x} {y:.1f}"
        d += f" L{W} {H} L0 {H} Z"
        body += f'<path d="{d}" fill="{colour}"/>'
    svg("collines", body, defs)


def boomerangs():
    r = random.Random(11)
    body = '<rect width="100%" height="100%" fill="#f7eef6"/>'
    shape = "M0 0 C 30 -6 58 6 70 30 C 62 26 52 24 44 26 C 40 12 22 4 0 8 Z"
    for row in range(-1, H // 130 + 2):
        for col in range(-1, W // 150 + 2):
            x = col * 150 + (75 if row % 2 else 0) + r.uniform(-12, 12)
            y = row * 130 + r.uniform(-12, 12)
            body += (f'<path d="{shape}" fill="#b4519f" opacity="0.18" '
                     f'transform="translate({x:.0f} {y:.0f}) rotate({r.uniform(-40, 40):.0f}) scale(1.1)"/>')
    svg("boomerangs", body)


def aurore():
    defs = ""
    body = '<rect width="100%" height="100%" fill="#eef1fb"/>'
    for i, (x, y, s, c) in enumerate([(250, 200, 420, "#b6a4f0"), (900, 260, 460, "#8fd3e8"),
                                       (600, 720, 520, "#f3a6c8"), (1100, 820, 380, "#a6e3c4")]):
        defs += (f'<radialGradient id="g{i}"><stop offset="0" stop-color="{c}" stop-opacity="0.9"/>'
                 f'<stop offset="1" stop-color="{c}" stop-opacity="0"/></radialGradient>')
        body += f'<circle cx="{x}" cy="{y}" r="{s}" fill="url(#g{i})"/>'
    svg("aurore", body, defs)


def nuit():
    r = random.Random(5)
    defs = ('<linearGradient id="n" x1="0" y1="0" x2="0" y2="1">'
            '<stop offset="0" stop-color="#2b2350"/><stop offset="1" stop-color="#4a2f62"/></linearGradient>')
    body = '<rect width="100%" height="100%" fill="url(#n)"/>'
    for _ in range(140):
        body += (f'<circle cx="{r.uniform(0, W):.0f}" cy="{r.uniform(0, H):.0f}" r="{r.uniform(0.8, 2.6):.1f}" '
                 f'fill="#ffffff" opacity="{r.uniform(0.3, 0.9):.2f}"/>')
    body += '<circle cx="980" cy="180" r="60" fill="#fdf3d0" opacity="0.9"/>'
    svg("nuit", body, defs)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for draw in (bulles, vagues, confettis, pois, collines, boomerangs, aurore, nuit):
        draw()
    print("backgrounds drawn")
