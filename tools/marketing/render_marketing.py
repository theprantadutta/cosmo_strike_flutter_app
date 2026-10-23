#!/usr/bin/env python3
"""Render the store marketing screenshots (Prism Noir style).

Each frame = near-black canvas + coloured glow + stars, a mono eyebrow, a
Syne headline whose last words carry the prism gradient, the COSMO/STRIKE
mark, and a real in-app screenshot inside a device frame. Rendered with
headless Chrome so text, gradients and shadows match the app exactly.

Usage (from the app root):
    python3 tools/marketing/render_marketing.py
Inputs : iphone_screenshots/, ipad_screenshots/ (raw simulator captures)
Outputs: app-store-screenshots/, app-store-ipad-screenshots/,
         play-store-screenshots/{phone,tablet-7in,tablet-10in}/
"""
import html
import os
import random
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
FONTS = ROOT / "assets" / "fonts"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
ROCKET = ROOT / "assets" / "images" / "brand"

# (eyebrow, line1, gradient line / words, glow colour, iphone shot, ipad shot)
SLIDES = [
    ("Arcade space shooter", "Dodge. Graze.", "Strike.", "#6B4BD8", "01_home", "01_home"),
    ("Fast-paced combat", "Blast through", "alien waves.", "#1F7A78", "02_gameplay_formation", "02_gameplay_formation"),
    ("Graze for points", "Fly close.", "Score big.", "#B0457F", "03_gameplay_graze", None),
    ("Multi-phase bosses", "Topple the", "bosses.", "#B0457F", None, "03_gameplay_boss"),
    ("4 sectors · 12 levels", "Conquer the", "campaign.", "#3E5BC7", "04_campaign", "04_campaign"),
    ("Ships & upgrades", "Build your", "perfect ship.", "#B88A2E", "08_hangar", "08_hangar"),
    ("Frontline seasons", "Push the", "Frontline.", "#9B3FC4", "07_frontline", "07_frontline"),
    ("Liveries & exhausts", "Make it", "yours.", "#C2662E", "09_armory_liveries", "09_armory_liveries"),
    ("Sector Cups", "Win the", "Sector Cups.", "#1F8A8A", "06_sector_cups", "06_sector_cups"),
    ("Global standings", "Top the", "Standings.", "#3E5BC7", "05_standings", "05_standings"),
    ("72 commendations", "Earn every", "commendation.", "#2E8A5C", "12_commendations", "12_commendations"),
]


def font_face(family, weight, file):
    return (f"@font-face{{font-family:'{family}';font-weight:{weight};"
            f"src:url('file://{FONTS / file}');}}")


CSS_FONTS = "".join([
    font_face("Syne", 800, "syne/Syne-800.ttf"),
    font_face("Syne", 700, "syne/Syne-700.ttf"),
    font_face("Plex", 500, "IBMPlexMono-Medium.ttf"),
    font_face("Plex", 600, "IBMPlexMono-SemiBold.ttf"),
])


def stars(w, h, seed, n=140):
    rnd = random.Random(seed)
    out = []
    for _ in range(n):
        x, y = rnd.random() * w, rnd.random() * h
        s = rnd.choice([1, 1, 1.5, 2, 2.5]) * w / 2556
        a = rnd.uniform(0.25, 0.8)
        out.append(f'<i style="left:{x:.0f}px;top:{y:.0f}px;width:{s:.1f}px;height:{s:.1f}px;opacity:{a:.2f}"></i>')
    return "".join(out)


def brand_mark():
    icon = ROCKET / "logo-mark-prism.png"
    img = f'<img src="file://{icon}">' if icon.exists() else ""
    return f'<div class="brand">COSMO<span>/</span>STRIKE{img}</div>'


def render(slide_idx, eyebrow, line1, line2, glow, shot, w, h, kind, out):
    """kind: phone | tablet. Layout picks itself from the canvas aspect."""
    tall = h / w > 0.62  # iPad-style 4:3 canvas: two-line headline block
    sw, sh = Image.open(shot).size
    u = w / 100.0  # 1vw-ish unit
    if tall:
        head_h = h * 0.285
        dev_h = h * 0.675
    else:
        head_h = h * 0.215
        dev_h = h * 0.745
    bezel = (0.011 if kind == "phone" else 0.009) * w
    max_dev_w = w * 0.86
    inner_h = dev_h - 2 * bezel
    inner_w = inner_h * sw / sh
    if inner_w + 2 * bezel > max_dev_w:
        inner_w = max_dev_w - 2 * bezel
        inner_h = inner_w * sh / sw
    dev_w, dev_h = inner_w + 2 * bezel, inner_h + 2 * bezel
    radius = dev_h * (0.115 if kind == "phone" else 0.045)
    top = head_h + (h - head_h - dev_h) * 0.45

    num = f"{slide_idx:02d} / {eyebrow.upper()}"
    if tall:
        headline = (f'<div class="h1">{html.escape(line1)}</div>'
                    f'<div class="h1 prism">{html.escape(line2)}</div>')
        head_block = (f'<div class="row">{brand_mark()}<div class="eyebrow">{html.escape(num)}</div></div>'
                      f'<div class="headline tall">{headline}</div>')
    else:
        headline = (f'<div class="h1">{html.escape(line1)} '
                    f'<span class="prism">{html.escape(line2)}</span></div>')
        head_block = (f'<div class="row"><div class="eyebrow">{html.escape(num)}</div>{brand_mark()}</div>'
                      f'<div class="headline">{headline}</div>')

    camera = '<b class="cam"></b>' if kind == "tablet" else ""
    fs_h1 = (5.5 if tall else 3.75) * u
    doc = f"""<!doctype html><html><head><meta charset="utf-8"><style>
{CSS_FONTS}
*{{margin:0;padding:0;box-sizing:border-box}}
html,body{{width:{w}px;height:{h}px;overflow:hidden;background:#0A0A0D}}
.bg{{position:absolute;inset:0;background:
 radial-gradient(ellipse {w*0.75:.0f}px {h*0.75:.0f}px at 62% 58%, {glow}70 0%, {glow}2e 40%, transparent 75%),
 radial-gradient(ellipse {w*0.5:.0f}px {h*0.5:.0f}px at 8% 0%, #ffffff08, transparent 70%),
 #0A0A0D}}
.stars i{{position:absolute;border-radius:50%;background:#fff}}
.head{{position:absolute;left:{4.3*u:.0f}px;right:{4.3*u:.0f}px;top:{(3.4 if tall else 2.6)*u:.0f}px}}
.row{{display:flex;justify-content:space-between;align-items:center}}
.eyebrow{{font-family:Plex;font-weight:500;font-size:{(1.15 if tall else 0.86)*u:.1f}px;letter-spacing:.2em;color:#9a9aa8}}
.brand{{font-family:Syne;font-weight:800;font-size:{(1.3 if tall else 0.95)*u:.1f}px;letter-spacing:.24em;color:#f4f3f7;display:flex;align-items:center;gap:{0.5*u:.0f}px}}
.brand span{{background:linear-gradient(90deg,#7CF5FF,#A78BFA);-webkit-background-clip:text;color:transparent}}
.brand img{{height:{(2.3 if tall else 1.35)*u:.0f}px}}
.headline{{margin-top:{(1.6 if tall else 0.55)*u:.0f}px}}
.h1{{font-family:Syne;font-weight:800;font-size:{fs_h1:.0f}px;line-height:1.02;letter-spacing:-.035em;color:#f4f3f7;white-space:nowrap}}
.prism{{background:linear-gradient(90deg,#7CF5FF 0%,#A78BFA 35%,#FF8AD8 70%,#FFD58A 100%);-webkit-background-clip:text;color:transparent}}
.device{{position:absolute;left:{(w-dev_w)/2:.0f}px;top:{top:.0f}px;width:{dev_w:.0f}px;height:{dev_h:.0f}px;
 border-radius:{radius:.0f}px;background:#050507;padding:{bezel:.0f}px;
 box-shadow:0 0 0 {max(2,w/1300):.0f}px #34343e, 0 0 {w*0.045:.0f}px {glow}66, 0 {w*0.012:.0f}px {w*0.04:.0f}px #000c}}
.device img{{display:block;width:100%;height:100%;border-radius:{max(radius-bezel, 6):.0f}px}}
.cam{{position:absolute;top:{bezel*0.42:.0f}px;left:50%;width:{bezel*0.32:.0f}px;height:{bezel*0.32:.0f}px;margin-left:-{bezel*0.16:.0f}px;border-radius:50%;background:#1c1c22}}
</style></head><body>
<div class="bg"></div><div class="stars">{stars(w, h, slide_idx)}</div>
<div class="head">{head_block}</div>
<div class="device">{camera}<img src="file://{shot}"></div>
</body></html>"""
    with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False) as f:
        f.write(doc)
        page = f.name
    tmp_png = out.with_suffix(".tmp.png")
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                    "--force-device-scale-factor=1", f"--window-size={w},{h}",
                    "--virtual-time-budget=4000", "--allow-file-access-from-files",
                    f"--screenshot={tmp_png}", f"file://{page}"],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    os.unlink(page)
    im = Image.open(tmp_png).convert("RGB")  # opaque: stores reject alpha
    if out.suffix == ".jpg":
        im.save(out, quality=93)
    else:
        im.save(out)
    tmp_png.unlink()


def main():
    jobs = []
    phone_slides = [s for s in SLIDES if s[4]]
    tablet_slides = [s for s in SLIDES if s[5]]
    for i, s in enumerate(phone_slides, 1):
        shot = ROOT / "iphone_screenshots" / f"{s[4]}.png"
        name = f"{i:02d}-{s[4]}"
        jobs.append((i, s, shot, 2868, 1320, "phone", ROOT / "app-store-screenshots" / f"{name}-2868x1320.png"))
        if i <= 8:
            jobs.append((i, s, shot, 2560, 1440, "phone", ROOT / "play-store-screenshots/phone" / f"{name}-2560x1440.jpg"))
    for i, s in enumerate(tablet_slides, 1):
        shot = ROOT / "ipad_screenshots" / f"{s[5]}.png"
        name = f"{i:02d}-{s[5]}"
        jobs.append((i, s, shot, 2752, 2064, "tablet", ROOT / "app-store-ipad-screenshots" / f"{name}-2752x2064.jpg"))
        if i <= 8:
            jobs.append((i, s, shot, 1920, 1080, "tablet", ROOT / "play-store-screenshots/tablet-7in" / f"{name}-1920x1080.jpg"))
            jobs.append((i, s, shot, 2560, 1440, "tablet", ROOT / "play-store-screenshots/tablet-10in" / f"{name}-2560x1440.jpg"))
    only = sys.argv[1:]  # optional filter: output path substrings
    for i, s, shot, w, h, kind, out in jobs:
        if only and not any(o in str(out) for o in only):
            continue
        out.parent.mkdir(parents=True, exist_ok=True)
        render(i, s[0], s[1], s[2], s[3], shot, w, h, kind, out)
        print(out.relative_to(ROOT))


if __name__ == "__main__":
    main()
