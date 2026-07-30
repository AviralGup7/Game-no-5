#!/usr/bin/env python3
"""
Deterministically generate launcher icons, adaptive layers, notification icon
and Play Store graphics.

Code-generated rather than sourced or AI-made: reproducible byte-for-byte, no
third-party licence, one-line rebrand. CI regenerates and fails on drift.

Design: a 2x2 futoshiki fragment showing 3 > 1 with a chevron between them.
The chevron IS the brand - it is the one visual that distinguishes futoshiki
from every other number-grid puzzle on the store.
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


def _font(px):
    for p in ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
              "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"]:
        if os.path.exists(p):
            return ImageFont.truetype(p, px)
    return ImageFont.load_default()


def draw_icon(size, pad_ratio=0.14, bg=CREAM, rounded=True, transparent=False):
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
    # two cells plus one gutter, matching the real board proportions
    gutter = avail * 0.20
    cell = (avail - gutter) / 2.0
    step = cell + gutter
    r = int(cell * 0.14)
    f = _font(int(cell * 0.62))

    def put(cx, cy, ch, filled):
        box = [cx, cy, cx+cell, cy+cell]
        if filled:
            d.rounded_rectangle(box, radius=r, fill=TEAL)
            fg = CREAM
        else:
            d.rounded_rectangle(box, radius=r, outline=TEAL_DEEP,
                                width=max(2, int(cell*0.075)))
            fg = INK
        if ch:
            bb = d.textbbox((0, 0), ch, font=f)
            d.text((cx+cell/2-(bb[2]-bb[0])/2-bb[0],
                    cy+cell/2-(bb[3]-bb[1])/2-bb[1]), ch, font=f, fill=fg)

    put(pad,        pad,        '3', True)
    put(pad+step,   pad,        '1', False)
    put(pad,        pad+step,   '',  False)
    put(pad+step,   pad+step,   '2', True)

    # the chevron between the top two cells: 3 > 1
    cx = pad + cell + gutter/2
    cy = pad + cell/2
    s  = gutter * 0.28
    wd = max(3, int(cell*0.10))
    d.line([(cx-s, cy-s), (cx+s, cy), (cx-s, cy+s)],
           fill=AMBER, width=wd, joint='curve')

    return img.resize((size, size), Image.LANCZOS)


def launcher():
    for folder, px in [('mipmap-mdpi',48), ('mipmap-hdpi',72),
                       ('mipmap-xhdpi',96), ('mipmap-xxhdpi',144),
                       ('mipmap-xxxhdpi',192)]:
        p = os.path.join(RES, folder); os.makedirs(p, exist_ok=True)
        draw_icon(px).save(os.path.join(p, 'ic_launcher.png'))

    # Adaptive foreground must sit in the 66/108 safe zone or it gets clipped.
    for folder, px in [('mipmap-mdpi',108), ('mipmap-hdpi',162),
                       ('mipmap-xhdpi',216), ('mipmap-xxhdpi',324),
                       ('mipmap-xxxhdpi',432)]:
        canvas = Image.new('RGBA', (px, px), (0,0,0,0))
        inner = int(px * 0.60)
        art = draw_icon(inner, pad_ratio=0.02, rounded=False, transparent=True)
        off = (px - inner)//2
        canvas.paste(art, (off, off), art)
        p = os.path.join(RES, folder); os.makedirs(p, exist_ok=True)
        canvas.save(os.path.join(p, 'ic_launcher_foreground.png'))


def notification():
    """Monochrome, transparent: Android tints it and discards colour."""
    for folder, px in [('drawable-mdpi',24), ('drawable-hdpi',36),
                       ('drawable-xhdpi',48), ('drawable-xxhdpi',72),
                       ('drawable-xxxhdpi',96)]:
        S = 8; W = px*S
        img = Image.new('RGBA', (W, W), (0,0,0,0))
        d = ImageDraw.Draw(img)
        gutter = W*0.18
        cell = (W - gutter)/2.0
        step = cell + gutter
        rr = int(cell*0.16)
        d.rounded_rectangle([0,0,cell,cell], radius=rr, fill=(255,255,255,255))
        d.rounded_rectangle([step,step,step+cell,step+cell], radius=rr,
                            fill=(255,255,255,255))
        for (x,y) in [(step,0),(0,step)]:
            d.rounded_rectangle([x,y,x+cell,y+cell], radius=rr,
                                outline=(255,255,255,255),
                                width=max(2,int(cell*0.14)))
        p = os.path.join(RES, folder); os.makedirs(p, exist_ok=True)
        img.resize((px,px), Image.LANCZOS).save(
            os.path.join(p,'ic_notification.png'))


def store():
    os.makedirs(BRAND, exist_ok=True)
    draw_icon(512).save(os.path.join(BRAND, 'play_icon_512.png'))

    W, H = 1024, 500
    img = Image.new('RGB', (W, H), CREAM)
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = y/H
        d.line([(0,y),(W,y)], fill=(int(246-8*t), int(250-10*t), int(249-10*t)))
    art = draw_icon(350)
    img.paste(art, (72, (H-350)//2), art)
    ft, fs = _font(74), _font(33)
    d.text((470, 148), "Large Print", font=ft, fill=TEAL_DEEP)
    d.text((470, 228), "Futoshiki",   font=ft, fill=TEAL_DEEP)
    d.text((474, 326), "Big numbers  ·  No timer  ·  Offline",
           font=fs, fill=(66, 78, 76))
    d.rounded_rectangle([474, 378, 690, 390], radius=6, fill=AMBER)
    img.save(os.path.join(BRAND, 'play_feature_1024x500.png'))


if __name__ == '__main__':
    launcher(); notification(); store()
    print('icons + store graphics generated')
