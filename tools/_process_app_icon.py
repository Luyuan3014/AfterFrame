"""Strip outer black canvas from app_icon.png and emit launcher / branding assets."""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(r'd:\Project\myProject\after_frame')
SRC = ROOT / 'assets' / 'icon' / 'app_icon.png'
OUT_FG = ROOT / 'assets' / 'icon' / 'app_icon_launcher.png'  # transparent subject
OUT_OPAQUE = ROOT / 'assets' / 'icon' / 'app_icon_launcher_opaque.png'
OUT_LOGO = ROOT / 'assets' / 'branding' / 'logo.png'
OUT_LOGO_FULL = ROOT / 'assets' / 'branding' / 'logo_full.png'
BRAND_GREEN = (220, 249, 71, 255)  # #DCF947


def flood_background_mask(arr: np.ndarray, luma_thresh: float = 40.0) -> np.ndarray:
    h, w = arr.shape[:2]
    luma = arr[:, :, :3].astype(np.float32).mean(axis=2)
    is_dark = luma < luma_thresh
    bg = np.zeros((h, w), dtype=bool)
    stack: list[tuple[int, int]] = []

    for x in range(w):
        stack.append((0, x))
        stack.append((h - 1, x))
    for y in range(h):
        stack.append((y, 0))
        stack.append((y, w - 1))

    while stack:
        y, x = stack.pop()
        if y < 0 or y >= h or x < 0 or x >= w:
            continue
        if bg[y, x] or not is_dark[y, x]:
            continue
        bg[y, x] = True
        stack.extend(((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)))
    return bg


def content_bbox(mask_keep: np.ndarray, pad: int = 4) -> tuple[int, int, int, int]:
    ys, xs = np.where(mask_keep)
    y0, y1 = int(ys.min()), int(ys.max())
    x0, x1 = int(xs.min()), int(xs.max())
    h, w = mask_keep.shape
    return (
        max(0, x0 - pad),
        max(0, y0 - pad),
        min(w - 1, x1 + pad),
        min(h - 1, y1 + pad),
    )


def fit_square(rgba: Image.Image, size: int, fill=(0, 0, 0, 0), fill_ratio: float = 0.99) -> Image.Image:
    canvas = Image.new('RGBA', (size, size), fill)
    target = max(1, int(size * fill_ratio))
    fitted = rgba.copy()
    fitted.thumbnail((target, target), Image.Resampling.LANCZOS)
    x = (size - fitted.width) // 2
    y = (size - fitted.height) // 2
    canvas.paste(fitted, (x, y), fitted)
    return canvas


def to_opaque_green(rgba: Image.Image) -> Image.Image:
    out = Image.new('RGBA', rgba.size, BRAND_GREEN)
    out.alpha_composite(rgba)
    return out.convert('RGB')


def main() -> None:
    im = Image.open(SRC).convert('RGBA')
    arr = np.array(im)
    bg = flood_background_mask(arr)

    transparent = arr.copy()
    transparent[bg, 3] = 0

    x0, y0, x1, y1 = content_bbox(~bg, pad=4)
    cropped = Image.fromarray(transparent).crop((x0, y0, x1 + 1, y1 + 1))

    cw, ch = cropped.size
    side = max(cw, ch)
    squared = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    squared.paste(cropped, ((side - cw) // 2, (side - ch) // 2), cropped)

    # Full-bleed subject so home-screen masks don't reveal outer canvas.
    # fill_ratio=1.0: crop box already equals the green squircle bounds.
    subject = fit_square(squared, 1024, fill=(0, 0, 0, 0), fill_ratio=1.0)
    subject.save(OUT_FG, 'PNG')
    to_opaque_green(subject).save(OUT_OPAQUE, 'PNG')

    logo_full = fit_square(squared, 1024, fill=(0, 0, 0, 0), fill_ratio=1.0)
    to_opaque_green(logo_full).save(OUT_LOGO_FULL, 'PNG')
    fit_square(squared, 512, fill=(0, 0, 0, 0), fill_ratio=1.0).save(OUT_LOGO, 'PNG')

    opaque = np.array(Image.open(OUT_OPAQUE))
    print('crop', x0, y0, x1, y1)
    print('opaque corner', opaque[0, 0].tolist(), 'center', opaque[512, 512].tolist())
    print('saved', OUT_FG)
    print('saved', OUT_OPAQUE)
    print('saved', OUT_LOGO)
    print('saved', OUT_LOGO_FULL)


if __name__ == '__main__':
    main()
