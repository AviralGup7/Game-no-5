#!/usr/bin/env python3
"""
Deterministically generate launcher icons, adaptive layers, notification icon
and Play Store graphics.

Code-generated rather than sourced or AI-made: reproducible byte-for-byte, no
third-party licence, one-line rebrand. CI regenerates and fails on drift.

Design: a half-solved 4x4 nonogram with its clue numbers down the left and
along the top. The filled squares form a heart, so the icon shows the ONE
thing that distinguishes this game from every other number-grid puzzle on the
store - the numbers around the edge turn into a picture.

Deliberately not a finished picture: a partly-filled grid reads as a puzzle
you could pick up, where a completed one reads as a logo.
"""
from PIL import Image, ImageDraw, ImageFont
import os

ROOT  = os.path.join(os.path.dirname(__file__), '..')
RES   = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res')
BRAND = os.path.join(ROOT, 'assets', 'branding')

TEAL_DEEP = (0, 56, 46)
TEAL      = (15, 107, 92)
CREAM     = (246, 250, 249)
INK       = (18, 30, 28)
AMBER     = (180, 83, 10)

# The 4x4 picture in the icon: a small heart.
#   row clues: 2 / 4 / 4 / 2   (top row is the two "lobes")
PICTURE = [
    [1, 1, 1, 1],
    [1, 1, 1, 1],
    [0, 1, 1, 0],
    [0, 1, 1, 0],
]
# Which squares are shown as already filled. The bottom two rows are left
# blank so the icon reads as in-progress.
DONE = [
    [1, 1, 1, 1],
    [1, 1, 1, 1],
    [0, 0, 0, 0],
    [0, 0, 0, 0],
]
ROW_CLUES = ['4', '4', '2', '2']
COL_CLUES = ['2', '4', '4', '2']


def _font(px):
    for p in ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
              "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"]:
        if os.path.exists(p):
            return ImageFont.truetype(p, px)
    return ImageFont.load_default()


def draw_icon(size, pad_ratio=0.11, bg=CREAM, rounded=True, transparent=False):
    """Supersampled 4x then downscaled, so edges stay clean at every density."""
    S = 4
    W = size * S
    img = Image.new('RGBA', (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if not transparent:
        if rounded:
            d.rounded_rectangle([0, 0, W-1, W-1], radius=int(W*0.22), fill=bg)
        else:
            d.rectangle([0, 0, W-1, W-1], fill=bg)

    pad = int(W * pad_ratio)
    avail = W - 2*pad
    # Clue strips take one cell-width each, matching the real board layout.
    n = 4
    cell = avail / (n + 1.0)
    gx = pad + cell          # grid origin x (after the left clue strip)
    gy = pad + cell          # grid origin y (below the top clue strip)

    fclue = _font(int(cell * 0.56))
    lw = max(2, int(cell * 0.055))

    # clue numbers
    for r in range(n):
        ch = ROW_CLUES[r]
        bb = d.textbbox((0, 0), ch, font=fclue)
        d.text((gx - cell*0.5 - (bb[2]-bb[0])/2 - bb[0],
                gy + r*cell + cell/2 - (bb[3]-bb[1])/2 - bb[1]),
               ch, font=fclue, fill=TEAL_DEEP)
    for c in range(n):
        ch = COL_CLUES[c]
        bb = d.textbbox((0, 0), ch, font=fclue)
        d.text((gx + c*cell + cell/2 - (bb[2]-bb[0])/2 - bb[0],
                gy - cell*0.5 - (bb[3]-bb[1])/2 - bb[1]),
               ch, font=fclue, fill=TEAL_DEEP)

    # filled squares
    rr = int(cell * 0.12)
    for r in range(n):
        for c in range(n):
            if DONE[r][c] and PICTURE[r][c]:
                box = [gx + c*cell + lw, gy + r*cell + lw,
                       gx + (c+1)*cell - lw, gy + (r+1)*cell - lw]
                d.rounded_rectangle(box, radius=rr, fill=TEAL)

    # one amber cross, the "ruled out" mark - the technique that solves these
    cxr, cxc = 2, 0
    x0 = gx + cxc*cell
    y0 = gy + cxr*cell
    m = cell * 0.30
    d.line([(x0+m, y0+m), (x0+cell-m, y0+cell-m)], fill=AMBER,
           width=max(3, int(cell*0.11)))
    d.line([(x0+cell-m, y0+m), (x0+m, y0+cell-m)], fill=AMBER,
           width=max(3, int(cell*0.11)))

    # grid lines, outer border heavier
    grid = TEAL_DEEP
    for i in range(n+1):
        x = gx + i*cell
        y = gy + i*cell
        w = lw*2 if i in (0, n) else lw
        d.line([(x, gy), (x, gy + n*cell)], fill=grid, width=w)
        d.line([(gx, y), (gx + n*cell, y)], fill=grid, width=w)

    return img.resize((size, size), Image.LANCZOS)


def launcher():
    for folder, px in [('mipmap-mdpi', 48), ('mipmap-hdpi', 72),
                       ('mipmap-xhdpi', 96), ('mipmap-xxhdpi', 144),
                       ('mipmap-xxxhdpi', 192)]:
        p = os.path.join(RES, folder)
        os.makedirs(p, exist_ok=True)
        draw_icon(px).save(os.path.join(p, 'ic_launcher.png'))

    # Adaptive foreground must sit in the 66/108 safe zone or it gets clipped
    # by the OEM mask.
    for folder, px in [('mipmap-mdpi', 108), ('mipmap-hdpi', 162),
                       ('mipmap-xhdpi', 216), ('mipmap-xxhdpi', 324),
                       ('mipmap-xxxhdpi', 432)]:
        canvas = Image.new('RGBA', (px, px), (0, 0, 0, 0))
        inner = int(px * 0.60)
        art = draw_icon(inner, pad_ratio=0.02, rounded=False, transparent=True)
        off = (px - inner)//2
        canvas.paste(art, (off, off), art)
        p = os.path.join(RES, folder)
        os.makedirs(p, exist_ok=True)
        canvas.save(os.path.join(p, 'ic_launcher_foreground.png'))


def notification():
    """Monochrome, transparent: Android tints it and discards colour."""
    for folder, px in [('drawable-mdpi', 24), ('drawable-hdpi', 36),
                       ('drawable-xhdpi', 48), ('drawable-xxhdpi', 72),
                       ('drawable-xxxhdpi', 96)]:
        S = 8
        W = px*S
        img = Image.new('RGBA', (W, W), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        # A 3x3 block pattern - legible at 24dp, where clue numbers would not
        # be.
        n = 3
        cell = W / n
        on = [[1, 1, 0], [1, 1, 1], [0, 1, 1]]
        rr = int(cell*0.16)
        pad = cell*0.06
        for r in range(n):
            for c in range(n):
                box = [c*cell+pad, r*cell+pad,
                       (c+1)*cell-pad, (r+1)*cell-pad]
                if on[r][c]:
                    d.rounded_rectangle(box, radius=rr, fill=(255, 255, 255, 255))
                else:
                    d.rounded_rectangle(box, radius=rr,
                                        outline=(255, 255, 255, 255),
                                        width=max(2, int(cell*0.13)))
        p = os.path.join(RES, folder)
        os.makedirs(p, exist_ok=True)
        img.resize((px, px), Image.LANCZOS).save(
            os.path.join(p, 'ic_notification.png'))


def store():
    os.makedirs(BRAND, exist_ok=True)
    draw_icon(512).save(os.path.join(BRAND, 'play_icon_512.png'))

    W, H = 1024, 500
    img = Image.new('RGB', (W, H), CREAM)
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = y/H
        d.line([(0, y), (W, y)],
               fill=(int(246-8*t), int(250-10*t), int(249-10*t)))
    art = draw_icon(350)
    img.paste(art, (72, (H-350)//2), art)
    ft, fs = _font(74), _font(30)
    d.text((470, 148), "Large Print", font=ft, fill=TEAL_DEEP)
    d.text((470, 228), "Nonogram", font=ft, fill=TEAL_DEEP)
    # No cognitive or medical claims, ever - Lumosity paid a $2M FTC
    # settlement for exactly that kind of copy.
    tag = "Big squares · No timer · Offline"
    d.text((474, 326), tag, font=fs, fill=(66, 78, 76))
    # Assert the strapline actually fits: an overflowing feature graphic is
    # rejected by Play review, and it is invisible in a thumbnail.
    right = d.textbbox((474, 326), tag, font=fs)[2]
    assert right < W - 24, f"feature graphic strapline overflows: {right}px"
    d.rounded_rectangle([474, 378, 690, 390], radius=6, fill=AMBER)
    img.save(os.path.join(BRAND, 'play_feature_1024x500.png'))


if __name__ == '__main__':
    launcher()
    notification()
    store()
    print('icons + store graphics generated')
