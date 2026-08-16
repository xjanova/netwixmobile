#!/usr/bin/env python3
"""
Generates the NetWix app icon set from geometry — no hand-exported bitmaps.

Why this file exists (2026-08-16): the shipped icon was a soft-shaded 3D "glossy play button"
raster. It read as generic stock art rather than a brand, and it carried three concrete defects:
  * the artwork was baked at one size, so every density was a resample of the same PNG;
  * the adaptive-icon foreground ignored the safe zone, so a circular launcher mask clipped it;
  * there was no monochrome layer, so Android 13+ themed icons fell back to a flat blob.

Drawing the mark from coordinates fixes all three at once and makes a re-tint or a nudge a
one-line change. Everything is rendered at 8x and downsampled (LANCZOS), which gives cleaner
edges than any exporter default.

Run:  python tool/brand/make_icons.py
"""

import math
import os
from PIL import Image, ImageDraw, ImageFilter

# ---- brand (mirrors lib/theme/tokens.dart — keep in step) -------------------
CRIMSON = (0xFF, 0x2D, 0x55)
CRIMSON_HI = (0xFF, 0x6B, 0x85)
VIOLET = (0xB0, 0x26, 0xFF)
VIOLET_HI = (0xCB, 0x6B, 0xFF)
INK = (0x07, 0x05, 0x0C)

SS = 8  # supersample factor

ROOT = os.path.join(os.path.dirname(__file__), '..', '..')
RES = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res')
BRAND = os.path.join(ROOT, 'assets', 'brand')

# Android adaptive icons are 108dp with only the middle 72dp guaranteed visible, so a circular
# launcher mask trims to ~66% of the canvas.
#
# Sizing the mark by its CIRCUMCIRCLE is the obvious reading of that rule and it is wrong here: a
# triangle inscribed in a circle fills barely 40% of it, so the icon came out technically safe and
# visibly timid, swimming in empty tile next to the artwork it replaced. What the rule actually
# requires is that no INK crosses the safe circle — and the corner rounding pulls the real
# silhouette well inside the circumcircle. Hence a larger figure, checked against the mask by
# verify() below rather than assumed.
SAFE = 0.74

# The in-app / store mark is a different job: it sits inside the app's own layouts, which supply
# their own spacing, so baking launcher padding into it only makes it look shrunken.
TIGHT = 0.94


def rounded_polygon(pts, r, steps=48):
    """Point list for `pts` with every corner replaced by a tangent arc of radius `r`."""
    out = []
    n = len(pts)
    for i in range(n):
        prev, cur, nxt = pts[(i - 1) % n], pts[i], pts[(i + 1) % n]
        v1 = (prev[0] - cur[0], prev[1] - cur[1])
        v2 = (nxt[0] - cur[0], nxt[1] - cur[1])
        l1 = math.hypot(*v1) or 1.0
        l2 = math.hypot(*v2) or 1.0
        u1 = (v1[0] / l1, v1[1] / l1)
        u2 = (v2[0] / l2, v2[1] / l2)

        # half-angle at this corner decides how far back the arc has to start
        ang = math.acos(max(-1.0, min(1.0, u1[0] * u2[0] + u1[1] * u2[1])))
        if ang < 1e-6 or abs(ang - math.pi) < 1e-6:
            out.append(cur)
            continue
        t = min(r / math.tan(ang / 2), l1 / 2, l2 / 2)
        p1 = (cur[0] + u1[0] * t, cur[1] + u1[1] * t)
        p2 = (cur[0] + u2[0] * t, cur[1] + u2[1] * t)

        bis = (u1[0] + u2[0], u1[1] + u2[1])
        bl = math.hypot(*bis) or 1.0
        bis = (bis[0] / bl, bis[1] / bl)
        d = t / math.cos(ang / 2) if math.cos(ang / 2) else 0
        centre = (cur[0] + bis[0] * d, cur[1] + bis[1] * d)
        rad = math.hypot(p1[0] - centre[0], p1[1] - centre[1])

        a1 = math.atan2(p1[1] - centre[1], p1[0] - centre[0])
        a2 = math.atan2(p2[1] - centre[1], p2[0] - centre[0])
        # always sweep the short way round, or the corner turns inside out
        while a2 - a1 > math.pi:
            a2 -= 2 * math.pi
        while a1 - a2 > math.pi:
            a2 += 2 * math.pi
        for s in range(steps + 1):
            a = a1 + (a2 - a1) * s / steps
            out.append((centre[0] + rad * math.cos(a), centre[1] + rad * math.sin(a)))
    return out


def gradient(size, stops, box=None):
    """
    Diagonal top-left → bottom-right ramp through `stops`, mapped across `box` (l,t,r,b).

    Mapping to the MARK's bounds rather than the whole canvas is the difference between the
    brand gradient and a wash: the mark sits in the middle of the tile, so a canvas-wide ramp
    only ever shows it the midpoint of the range — the first cut of this icon came out uniformly
    pink with none of the crimson the brand is built on.
    """
    l, t, r, b = box or (0, 0, size - 1, size - 1)
    span = max((r - l) + (b - t), 1)
    g = Image.new('RGB', (size, size))
    px = g.load()
    n = len(stops) - 1
    for y in range(size):
        for x in range(size):
            u = min(1.0, max(0.0, ((x - l) + (y - t)) / span))
            seg = min(int(u * n), n - 1)
            f = u * n - seg
            c0, c1 = stops[seg], stops[seg + 1]
            px[x, y] = tuple(int(c0[i] + (c1[i] - c0[i]) * f) for i in range(3))
    return g


def triangle_pts(cx, cy, r, rot=-90.0):
    """Equilateral triangle on a circumcircle — the play mark and its frame share this."""
    return [
        (cx + r * math.cos(math.radians(rot + 120 * k)),
         cy + r * math.sin(math.radians(rot + 120 * k)))
        for k in range(3)
    ]


def mark_mask(size, ring=True, scale=None):
    """
    The NetWix mark: a rounded triangular frame around a solid play triangle.

    Keeping the outer frame and the inner play head on the SAME equilateral geometry (just
    different radii, rotated to point right) is what makes it read as one deliberate mark
    rather than two shapes that happen to be nested.
    """
    S = size * SS
    m = Image.new('L', (S, S), 0)
    d = ImageDraw.Draw(m)

    cx = cy = S / 2
    outer_r = S * (scale if scale is not None else SAFE) / 2

    # Optical centre: an equilateral triangle's centroid sits above its visual middle, and a
    # right-pointing one also looks left-heavy. Nudging right/down is what stops the finished
    # icon from looking like it slid off the tile.
    cx += S * 0.012
    cy += S * 0.004

    outer = triangle_pts(cx, cy, outer_r, rot=0)  # points right
    d.polygon(rounded_polygon(outer, outer_r * 0.30), fill=255)

    if ring:
        inner_r = outer_r * 0.60
        inner = triangle_pts(cx, cy, inner_r, rot=0)
        d.polygon(rounded_polygon(inner, inner_r * 0.30), fill=0)

        play_r = outer_r * 0.40
        play = triangle_pts(cx + S * 0.006, cy, play_r, rot=0)
        d.polygon(rounded_polygon(play, play_r * 0.26), fill=255)

    return m.resize((size, size), Image.LANCZOS)


def foreground(size, scale=None):
    """Gradient-filled mark on transparency — the adaptive foreground layer."""
    mask = mark_mask(size, scale=scale)
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    grad = gradient(size, [CRIMSON_HI, CRIMSON, VIOLET, VIOLET_HI], mask.getbbox()).convert('RGBA')
    img.paste(grad, (0, 0), mask)

    # A single soft violet bloom behind the mark — the one lighting cue kept from the old
    # icon, because a flat mark on flat ink reads as a sticker. No bevels, no specular.
    glow = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    r = size * 0.24
    gd.ellipse([size / 2 - r, size / 2 - r, size / 2 + r, size / 2 + r], fill=VIOLET + (44,))
    # Tight and faint on purpose: a wide bloom turns into visible haze once the launcher scales
    # the icon down to 48px, and haze around a silhouette is what makes an icon look homemade.
    glow = glow.filter(ImageFilter.GaussianBlur(size * 0.055))

    return Image.alpha_composite(glow, img)


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, 'PNG', optimize=True)
    print('  %-58s %5.1f KB' % (os.path.relpath(path, ROOT), os.path.getsize(path) / 1024))


def verify():
    """Fail loudly if any ink would be clipped by a circular launcher mask."""
    dp = 432
    a = foreground(dp).split()[-1]  # alpha
    px = a.load()
    r_safe = dp * 0.66 / 2
    cx = cy = dp / 2
    worst = 0.0
    for y in range(dp):
        for x in range(dp):
            if px[x, y] > 8:
                worst = max(worst, math.hypot(x - cx, y - cy) / r_safe)
    pct = worst * 100
    print('  safe-circle usage: %.1f%% %s' % (pct, 'OK' if worst <= 1.0 else '** CLIPPED **'))
    if worst > 1.0:
        raise SystemExit('mark exceeds the adaptive safe circle — reduce SAFE')


def main():
    # Adaptive foreground/monochrome: 108dp canvas at each density bucket.
    for bucket, dp in [('mdpi', 108), ('hdpi', 162), ('xhdpi', 216),
                       ('xxhdpi', 324), ('xxxhdpi', 432)]:
        save(foreground(dp), os.path.join(RES, 'drawable-%s' % bucket, 'ic_launcher_foreground.png'))

        # Themed icons (Android 13+) tint a monochrome layer; a white-on-transparent silhouette
        # is what the system expects. Without this the launcher renders a plain filled shape.
        mono = Image.new('RGBA', (dp, dp), (0, 0, 0, 0))
        mono.paste(Image.new('RGBA', (dp, dp), (255, 255, 255, 255)), (0, 0), mark_mask(dp))
        save(mono, os.path.join(RES, 'drawable-%s' % bucket, 'ic_launcher_monochrome.png'))

    # Legacy square launcher icons (pre-26 devices) — mark on the brand ink.
    for bucket, px in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96),
                       ('xxhdpi', 144), ('xxxhdpi', 192)]:
        base = Image.new('RGBA', (px, px), INK + (255,))
        save(Image.alpha_composite(base, foreground(px)),
             os.path.join(RES, 'mipmap-%s' % bucket, 'ic_launcher.png'))

    # In-app + store artwork — drawn TIGHT, no launcher padding.
    save(foreground(512, scale=TIGHT), os.path.join(BRAND, 'netwix-icon.png'))
    store = Image.new('RGBA', (512, 512), INK + (255,))
    save(Image.alpha_composite(store, foreground(512, scale=TIGHT)),
         os.path.join(ROOT, 'tool', 'brand', 'play-store-512.png'))


if __name__ == '__main__':
    main()
    verify()
