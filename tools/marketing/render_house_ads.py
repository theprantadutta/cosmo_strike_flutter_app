#!/usr/bin/env python3
"""Render AdMob house-ad creatives for Cosmo Strike (Prism Noir style).

House ads promote Cosmo Strike inside the owner's other apps (Snake Classic,
...). They are static images, so the same file works on Android and iOS; only
the click-through URL differs per platform (see marketing/house-ads/README.md).

Usage (from the app root):
    python tools/marketing/render_house_ads.py
Inputs : android_phone_screenshots/ (raw A24 captures, 2340x1080),
         marketing/cross-promo/cosmo-strike-icon-512.png
Outputs: marketing/house-ads/*.png|jpg at the exact AdMob sizes.

Policy: no reward, no fake close/download buttons, no system-style alerts.
The only button-like element is a plain "Play free" label, which is the
real action of the ad.
"""
import os
import subprocess
import tempfile
from pathlib import Path

from PIL import Image

import render_marketing as rm

ROOT = rm.ROOT
OUT = ROOT / "marketing" / "house-ads"
SHOTS = ROOT / "android_phone_screenshots"
ICON = (ROOT / "marketing" / "cross-promo" / "cosmo-strike-icon-512.png").as_uri()

PRISM = "linear-gradient(90deg,#7CF5FF 0%,#A78BFA 35%,#FF8AD8 70%,#FFD58A 100%)"


def shot(name):
    return (SHOTS / f"{name}.png").resolve().as_uri()


def base_css(w, h, glow="#6B4BD8"):
    return f"""{rm.CSS_FONTS}
*{{margin:0;padding:0;box-sizing:border-box}}
html,body{{width:{w}px;height:{h}px;overflow:hidden;background:#0A0A0D}}
body{{position:relative;font-family:Plex;color:#f4f3f7}}
.bg{{position:absolute;inset:0;background:radial-gradient(ellipse at 50% 0%,{glow}55 0%,transparent 65%),#0A0A0D}}
.prism{{background:{PRISM};-webkit-background-clip:text;color:transparent}}
.name{{font-family:Syne;font-weight:800;letter-spacing:-.02em;white-space:nowrap}}
.eyebrow{{font-family:Plex;font-weight:600;text-transform:uppercase;letter-spacing:.14em;color:#b9b6c8;white-space:nowrap}}
.cta{{display:inline-flex;align-items:center;justify-content:center;font-family:Plex;font-weight:600;
 color:#0A0A0D;background:{PRISM};white-space:nowrap}}
.icon{{display:block;border-radius:22%;box-shadow:0 0 0 1px #34343e}}
.shot{{display:block;object-fit:cover;box-shadow:0 0 0 1px #34343e}}
"""


def banner(w, h):
    """Leaderboard-style strip: icon, name + line, CTA."""
    s = h / 50
    line = "Arcade space shooter" if w / s < 400 else "Arcade space shooter · plays offline"
    return f"""<style>{base_css(w, h)}
.row{{position:absolute;inset:0;display:flex;align-items:center;padding:0 {8*s:.0f}px;gap:{8*s:.0f}px}}
.icon{{width:{38*s:.0f}px;height:{38*s:.0f}px;flex:none}}
.txt{{flex:1;min-width:0;overflow:hidden}}
.name{{font-size:{16*s:.0f}px;line-height:1}}
.line{{font-size:{9.5*s:.0f}px;color:#b9b6c8;margin-top:{4*s:.0f}px;white-space:nowrap}}
.cta{{flex:none;font-size:{10.5*s:.0f}px;height:{26*s:.0f}px;padding:0 {10*s:.0f}px;border-radius:{13*s:.0f}px}}
</style><div class="bg"></div><div class="row">
<img class="icon" src="{ICON}"><div class="txt"><div class="name">Cosmo <span class="prism">Strike</span></div>
<div class="line">{line}</div></div><div class="cta">Play free</div></div>"""


def medium_rect(w, h):
    """300x250: gameplay on top, identity row, full-width CTA."""
    return f"""<style>{base_css(w, h, "#B0457F")}
.shot{{position:absolute;left:10px;top:10px;width:{w-20}px;height:118px;border-radius:8px}}
.row{{position:absolute;left:12px;right:12px;top:138px;display:flex;align-items:center;gap:10px}}
.icon{{width:46px;height:46px;flex:none}}
.name{{font-size:19px;line-height:1}}
.line{{font-size:10px;color:#b9b6c8;margin-top:5px;white-space:nowrap}}
.cta{{position:absolute;left:12px;right:12px;bottom:12px;font-size:12px;height:32px;border-radius:16px}}
</style><div class="bg"></div><img class="shot" src="{shot('03_gameplay_graze')}">
<div class="row"><img class="icon" src="{ICON}"><div><div class="name">Cosmo <span class="prism">Strike</span></div>
<div class="line">Graze bullets, topple bosses.</div></div></div><div class="cta">Play free</div>"""


def interstitial_portrait(w, h):
    """Headline, gameplay frames that flex to the space left, identity + CTA."""
    u = w / 320
    two = h / w >= 1.45  # 2:3 has room for two frames, 3:4 for one
    frames = f'<img class="shot" src="{shot("02_gameplay_formation")}">'
    if two:
        frames += f'<img class="shot" src="{shot("04_gameplay_boss")}">'
    return f"""<style>{base_css(w, h)}
.wrap{{position:absolute;inset:0;padding:{20*u:.0f}px {16*u:.0f}px;display:flex;flex-direction:column;align-items:center}}
.eyebrow{{font-size:{9*u:.0f}px}}
.h1{{font-family:Syne;font-weight:800;font-size:{24*u:.0f}px;line-height:1.02;letter-spacing:-.03em;text-align:center;margin-top:{6*u:.0f}px;white-space:nowrap}}
.frames{{flex:1;min-height:0;width:100%;display:flex;flex-direction:column;justify-content:center;gap:{8*u:.0f}px;margin:{12*u:.0f}px 0}}
.shot{{width:100%;flex:0 1 auto;min-height:0;aspect-ratio:2340/1080;border-radius:{8*u:.0f}px}}
.id{{display:flex;align-items:center;gap:{10*u:.0f}px}}
.icon{{width:{44*u:.0f}px;height:{44*u:.0f}px;flex:none}}
.name{{font-size:{22*u:.0f}px;line-height:1}}
.line{{font-size:{9.5*u:.0f}px;color:#b9b6c8;margin-top:{4*u:.0f}px;white-space:nowrap}}
.cta{{font-size:{13*u:.0f}px;height:{38*u:.0f}px;width:100%;border-radius:{19*u:.0f}px;margin-top:{12*u:.0f}px}}
</style><div class="bg"></div><div class="wrap">
<div class="eyebrow">Arcade space shooter</div>
<div class="h1">Dodge. Graze.<br><span class="prism">Strike.</span></div>
<div class="frames">{frames}</div>
<div class="id"><img class="icon" src="{ICON}"><div><div class="name">Cosmo <span class="prism">Strike</span></div>
<div class="line">12 levels · bosses · offline</div></div></div>
<div class="cta">Play free</div></div>"""


def interstitial_landscape(w, h):
    """Full-bleed gameplay with a dark scrim and text on the left."""
    u = h / 320
    return f"""<style>{base_css(w, h)}
.full{{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;object-position:82% 50%}}
.scrim{{position:absolute;inset:0;background:linear-gradient(90deg,#0A0A0D 0%,#0A0A0D 40%,#0A0A0Dcc 55%,#0A0A0D22 80%,transparent 100%)}}
.col{{position:absolute;left:{26*u:.0f}px;top:0;bottom:0;display:flex;flex-direction:column;justify-content:center}}
.icon{{width:{58*u:.0f}px;height:{58*u:.0f}px}}
.eyebrow{{font-size:{9*u:.0f}px;margin-top:{14*u:.0f}px}}
.h1{{font-family:Syne;font-weight:800;font-size:{34*u:.0f}px;line-height:1.02;letter-spacing:-.03em;margin-top:{6*u:.0f}px}}
.line{{font-size:{10*u:.0f}px;color:#cfcbe0;margin-top:{10*u:.0f}px}}
.cta{{font-size:{13*u:.0f}px;height:{38*u:.0f}px;padding:0 {26*u:.0f}px;border-radius:{19*u:.0f}px;margin-top:{16*u:.0f}px;align-self:flex-start}}
</style><img class="full" src="{shot('04_gameplay_boss')}"><div class="scrim"></div>
<div class="col"><img class="icon" src="{ICON}"><div class="eyebrow">Cosmo Strike · arcade shooter</div>
<div class="h1">Fly close.<br><span class="prism">Score big.</span></div>
<div class="line">Graze bullets, chain kills,<br>topple the bosses.</div>
<div class="cta">Play free</div></div>"""


CREATIVES = [
    # (file, w, h, builder)
    ("banner_320x50.png", 320, 50, banner),
    ("banner_468x60.png", 468, 60, banner),
    ("banner_728x90.png", 728, 90, banner),
    ("mrec_300x250.jpg", 300, 250, medium_rect),
    ("interstitial_320x480.jpg", 320, 480, interstitial_portrait),
    ("interstitial_768x1024.jpg", 768, 1024, interstitial_portrait),
    ("interstitial_480x320.jpg", 480, 320, interstitial_landscape),
    ("interstitial_1024x768.jpg", 1024, 768, interstitial_landscape),
]


def render(file, w, h, builder):
    # builder returns <style>..</style> + markup; put markup in body.
    style, _, markup = builder(w, h).partition("</style>")
    doc = (f"<!doctype html><html><head><meta charset='utf-8'>{style}</style></head>"
           f"<body>{markup}</body></html>")
    with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False, encoding="utf-8") as f:
        f.write(doc)
        page = f.name
    out = OUT / file
    tmp = out.with_suffix(".tmp.png")
    subprocess.run([rm.CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                    "--force-device-scale-factor=1", f"--window-size={w},{h}",
                    "--virtual-time-budget=4000", "--allow-file-access-from-files",
                    f"--screenshot={tmp}", Path(page).resolve().as_uri()],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    os.unlink(page)
    im = Image.open(tmp).convert("RGB").crop((0, 0, w, h))
    if out.suffix == ".jpg":
        im.save(out, quality=88, optimize=True)
    else:
        im.save(out, optimize=True)
    tmp.unlink()
    print(f"{file}: {out.stat().st_size // 1024} KB")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for c in CREATIVES:
        render(*c)


if __name__ == "__main__":
    main()
