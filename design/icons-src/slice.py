"""Cut a 3x3 ChatGPT icon sheet (RGBA) into square app icons.

usage: python -I slice.py <sheet.png> <out_dir> name1 ... name9

Each cell keeps only its largest alpha blob (plus anything touching it after a small dilation),
which drops the stray glow specks ChatGPT leaves between icons, then is centred on a square
transparent canvas and resized to 192 px.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

SIZE = 192
PAD = 0.06


def cut(cell: Image.Image) -> Image.Image:
    a = np.asarray(cell)[..., 3]
    mask = a > 48
    labels, n = ndimage.label(mask)
    if n == 0:
        raise SystemExit('empty cell')
    sizes = ndimage.sum(mask, labels, range(1, n + 1))
    keep = labels == (int(np.argmax(sizes)) + 1)
    # Grow the main blob so soft edges and attached sparkles survive, then drop the rest.
    grown = ndimage.binary_dilation(keep, iterations=10)
    near = np.isin(labels, np.unique(labels[grown & mask]))
    keep = ndimage.binary_dilation(near, iterations=3) & (a > 0)
    px = np.asarray(cell).copy()
    px[..., 3] = np.where(keep, px[..., 3], 0)
    ys, xs = np.nonzero(px[..., 3] > 8)
    box = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
    icon = Image.fromarray(px).crop(box)
    side = int(max(icon.size) * (1 + 2 * PAD))
    canvas = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    canvas.paste(icon, ((side - icon.width) // 2, (side - icon.height) // 2), icon)
    return canvas.resize((SIZE, SIZE), Image.LANCZOS)


def main() -> None:
    sheet = Image.open(sys.argv[1]).convert('RGBA')
    if np.asarray(sheet)[..., 3].min() == 255:
        raise SystemExit('sheet has no transparency')
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    names = sys.argv[3:]
    w, h = sheet.size
    for i, name in enumerate(names):
        r, c = divmod(i, 3)
        cell = sheet.crop((c * w // 3, r * h // 3, (c + 1) * w // 3, (r + 1) * h // 3))
        cut(cell).save(out / f'{name}.png', optimize=True)
        print(name, (out / f'{name}.png').stat().st_size)


if __name__ == '__main__':
    main()
