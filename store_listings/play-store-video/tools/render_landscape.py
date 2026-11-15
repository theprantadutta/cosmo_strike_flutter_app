"""Cosmo Strike Play Store promo video, LANDSCAPE 1920x1080 (Prism Noir).

Adapted from Snake Classic's render_landscape.py. Cosmo's recordings are
themselves landscape (A24: 2340x1080), so the caption band sits on top and
the footage fills the frame below it.

Usage (from this folder):
  python -I render_landscape.py <ffmpeg.exe> scenes.json ../cosmo-strike-promo-landscape.mp4
"""

import json
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

D = Path(__file__).parent
APP = D.parents[2]
FONTS = APP / "assets" / "fonts"
FF, SCENES, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
MUSIC = D.parent / "music" / "Cyborg Ninja.mp3"
W, H = 1920, 1080

# Prism Noir tokens (lib/theme/cosmo_theme.dart)
BG = (10, 10, 13)
INK = (244, 244, 247)
INK70 = (184, 184, 189)
INK45 = (125, 125, 132)
HAIR = (40, 40, 48)
CYAN, VIOLET, PINK, GOLD, MINT = (124, 245, 255), (167, 139, 250), (255, 138, 216), (255, 213, 138), (155, 255, 200)
PRISM = [CYAN, VIOLET, PINK, GOLD]
CHIP_COLORS = {"cyan": CYAN, "violet": VIOLET, "pink": PINK, "gold": GOLD, "mint": MINT}

INTRO, OUTRO, FADE = 3.0, 5.0, 0.3

# Footage box (landscape recording)
FW, FH = 1600, 738
FX, FY = (W - FW) // 2, 296
RADIUS = 26
CAP_X = FX


def syne(w, s):
    return ImageFont.truetype(str(FONTS / "syne" / f"Syne-{w}.ttf"), s)


def mono(name, s):
    return ImageFont.truetype(str(FONTS / f"IBMPlexMono-{name}.ttf"), s)


def gradient(w, h, stops=PRISM):
    """Horizontal prism gradient image."""
    img = Image.new("RGB", (w, h))
    px = img.load()
    n = len(stops) - 1
    for x in range(w):
        t = x / max(1, w - 1) * n
        i = min(int(t), n - 1)
        f = t - i
        a, b = stops[i], stops[i + 1]
        c = tuple(round(a[k] + (b[k] - a[k]) * f) for k in range(3))
        for y in range(h):
            px[x, y] = c
    return img


def prism_text(img, xy, text, f, anchor="la"):
    d = ImageDraw.Draw(img)
    box = [round(v) for v in d.textbbox(xy, text, font=f, anchor=anchor)]
    w, h = box[2] - box[0], box[3] - box[1]
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).text(xy, text, font=f, fill=255, anchor=anchor)
    grad = gradient(max(1, w), max(1, h))
    layer = Image.new("RGB", img.size, BG)
    layer.paste(grad, (box[0], box[1]))
    img.paste(layer, (0, 0), mask)
    return box


def spaced(d, xy, text, f, fill, spacing, anchor="lm"):
    x, y = xy
    for ch in text:
        d.text((x, y), ch, font=f, fill=fill, anchor=anchor)
        x += d.textlength(ch, font=f) + spacing
    return x


def spaced_width(d, text, f, spacing):
    return sum(d.textlength(c, font=f) + spacing for c in text) - spacing


def background():
    img = Image.new("RGB", (W, H), BG)
    stars = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(stars)
    import random
    rnd = random.Random(7)
    for _ in range(220):
        x, y = rnd.randrange(W), rnd.randrange(H)
        a = rnd.randrange(40, 150)
        sd.point((x, y), fill=(255, 255, 255, a))
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((1100, -500, 2400, 500), fill=VIOLET + (46,))
    gd.ellipse((-500, 200, 600, 1300), fill=CYAN + (22,))
    glow = glow.filter(ImageFilter.GaussianBlur(160))
    img.paste(glow, (0, 0), glow)
    img.paste(stars, (0, 0), stars)
    return img


def stage_assets():
    bg = background()
    halo = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(halo).rounded_rectangle(
        (FX - 18, FY - 18, FX + FW + 18, FY + FH + 18), radius=RADIUS + 18, fill=VIOLET + (60,))
    halo = halo.filter(ImageFilter.GaussianBlur(30))
    bg.paste(halo, (0, 0), halo)
    # 2px prism frame
    frame_mask = Image.new("L", (W, H), 0)
    fm = ImageDraw.Draw(frame_mask)
    fm.rounded_rectangle((FX - 2, FY - 2, FX + FW + 1, FY + FH + 1), radius=RADIUS + 2, fill=255)
    fm.rounded_rectangle((FX, FY, FX + FW - 1, FY + FH - 1), radius=RADIUS, fill=0)
    grad = Image.new("RGB", (W, H), BG)
    grad.paste(gradient(FW + 4, FH + 4), (FX - 2, FY - 2))
    bg.paste(grad, (0, 0), frame_mask)
    bg.save(D / "lstage.png")
    mask = Image.new("L", (FW, FH), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, FW - 1, FH - 1), radius=RADIUS, fill=255)
    mask.save(D / "lmask.png")


def caption_png(i, label, color, title, sub):
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    fl = mono("Medium", 26)
    col = CHIP_COLORS.get(color, CYAN)
    y = 86
    d.ellipse((CAP_X, y - 7, CAP_X + 14, y + 7), fill=col)
    spaced(d, (CAP_X + 30, y), label.upper(), fl, col, 6)
    d.text((CAP_X - 3, 116), title, font=syne(800, 78), fill=INK)
    d.text((CAP_X, 214), sub, font=syne(600, 34), fill=INK70)
    p = D / f"lcap{i}.png"
    img.save(p)
    return p


def mark(size):
    return Image.open(APP / "docs" / "store" / "logo-mark-prism-flat.png").convert("RGBA").resize(
        (size, size), Image.LANCZOS)


def card(name, build):
    img = background()
    d = ImageDraw.Draw(img)
    build(img, d)
    p = D / f"{name}.png"
    img.save(p)
    return p


def wordmark(img, d, cx, y, size):
    f = syne(800, size)
    a, b = "COSMO", "/STRIKE"
    sp = round(size * 0.14)
    wa, wb = spaced_width(d, a, f, sp), spaced_width(d, b, f, sp)
    x0 = cx - (wa + sp + wb) / 2
    spaced(d, (x0, y), a, f, INK, sp)
    x = x0 + wa + sp
    for ch in b:
        if ch == "/":
            prism_text(img, (x, y), ch, f, anchor="lm")
        else:
            d.text((x, y), ch, font=f, fill=INK, anchor="lm")
        x += d.textlength(ch, font=f) + sp


def intro(img, d):
    m = mark(170)
    img.paste(m, ((W - 170) // 2, 170), m)
    wordmark(img, d, W / 2, 430, 46)
    f = syne(800, 128)
    l1 = "Dodge. Graze."
    w1 = d.textlength(l1, font=f)
    d.text(((W - w1) / 2, 520), l1, font=f, fill=INK)
    w2 = d.textlength("Strike.", font=f)
    prism_text(img, ((W - w2) / 2, 670), "Strike.", f)
    lbl = "ARCADE SPACE SHOOTER"
    fl = mono("Medium", 28)
    spaced(d, ((W - spaced_width(d, lbl, fl, 8)) / 2, 900), lbl, fl, INK45, 8)


def outro(img, d):
    m = mark(120)
    img.paste(m, (180, 150), m)
    d.text((330, 168), "Cosmo Strike", font=syne(800, 84), fill=INK)
    items = ["12-level campaign, 4 sectors", "Telegraphed multi-phase bosses",
             "Graze fire, charge Overdrive", "Daily Run & Sector Cups"]
    fi = syne(700, 46)
    y = 380
    for t in items:
        d.ellipse((190, y + 12, 210, y + 32), fill=MINT)
        d.text((240, y + 22), t, font=fi, fill=INK, anchor="lm")
        y += 92
    bw, bh, bx, by = 600, 132, 1150, 400
    d.rounded_rectangle((bx, by, bx + bw, by + bh), radius=bh // 2, fill=INK)
    ft = syne(800, 50)
    txt = "PLAY FREE"
    spaced(d, (bx + (bw - spaced_width(d, txt, ft, 6)) / 2, by + bh / 2), txt, ft, BG, 6)
    fl = mono("Medium", 28)
    sub = "GOOGLE PLAY & APP STORE"
    spaced(d, (bx + (bw - spaced_width(d, sub, fl, 6)) / 2, by + bh + 60), sub, fl, INK70, 6)
    credit = "Music: \"Cyborg Ninja\" Kevin MacLeod (incompetech.com) · CC BY 4.0"
    fc = mono("Regular", 22)
    d.text(((W - d.textlength(credit, font=fc)) / 2, H - 60), credit, font=fc, fill=INK45)


def main():
    scenes = json.loads(Path(SCENES).read_text(encoding="utf-8"))["segments"]
    stage_assets()
    caps = [caption_png(i, s["chip"], s.get("color", "cyan"), s["title"], s["sub"])
            for i, s in enumerate(scenes)]
    intro_p, outro_p = card("lintro", intro), card("loutro", outro)

    durs = [s["b"] - s["a"] for s in scenes]
    demo_len = sum(durs)
    total = INTRO + demo_len + OUTRO

    srcs = sorted({s["src"] for s in scenes})
    inputs, idx = [], {}
    for sp in srcs:
        idx[sp] = len(inputs) // 2
        inputs += ["-i", str(D / sp)]
    n_src = len(srcs)
    inputs += ["-loop", "1", "-i", str(D / "lstage.png")]
    inputs += ["-i", str(D / "lmask.png")]
    inputs += ["-loop", "1", "-t", str(INTRO), "-i", str(intro_p)]
    inputs += ["-loop", "1", "-t", str(OUTRO), "-i", str(outro_p)]
    cap0 = n_src + 4
    for p, du in zip(caps, durs):
        inputs += ["-loop", "1", "-t", f"{du:.3f}", "-i", str(p)]
    music_i = cap0 + len(scenes)
    inputs += ["-stream_loop", "-1", "-i", str(MUSIC)]

    fc = []
    uses = {sp: [i for i, s in enumerate(scenes) if s["src"] == sp] for sp in srcs}
    for sp, ids in uses.items():
        k = idx[sp]
        outs = "".join(f"[r{i}]" for i in ids)
        fc.append(f"[{k}:v]fps=30,split={len(ids)}{outs}" if len(ids) > 1 else f"[{k}:v]fps=30{outs}")
    for i, s in enumerate(scenes):
        fc.append(f"[r{i}]trim={s['a']}:{s['b']},setpts=PTS-STARTPTS[t{i}]")
    fc.append("".join(f"[t{i}]" for i in range(len(scenes))) + f"concat=n={len(scenes)}:v=1:a=0[rec]")
    fc.append(f"[rec]scale={FW}:{FH}:flags=lanczos,format=rgba[ph]")
    fc.append(f"[{n_src + 1}:v]format=gray[mk]")
    fc.append("[ph][mk]alphamerge[phr]")
    fc.append(f"[{n_src}:v]fps=30,trim=0:{demo_len:.3f},setpts=PTS-STARTPTS[stg]")
    fc.append(f"[stg][phr]overlay={FX}:{FY}:shortest=1[a0]")
    last, t = "a0", 0.0
    for i, du in enumerate(durs):
        fades = f"fade=in:st=0:d={FADE}:alpha=1,fade=out:st={du - FADE:.3f}:d={FADE}:alpha=1"
        fc.append(f"[{cap0 + i}:v]format=rgba,{fades},setpts=PTS-STARTPTS+{t:.3f}/TB[c{i}]")
        fc.append(f"[{last}][c{i}]overlay=0:0:eof_action=pass[b{i}]")
        last, t = f"b{i}", t + du
    fc.append(f"color=c=0xA78BFA:s={W}x6:r=30:d={demo_len:.3f}[bar]")
    fc.append(f"[{last}][bar]overlay=x='-{W}+{W}*t/{demo_len:.3f}':y={H - 6}:shortest=1,"
              f"format=yuv420p,setsar=1[demo]")
    fc.append(f"[{n_src + 2}:v]fps=30,format=yuv420p,fade=in:st=0:d=0.35,fade=out:st={INTRO - 0.35}:d=0.35,setsar=1[in]")
    fc.append(f"[{n_src + 3}:v]fps=30,format=yuv420p,fade=in:st=0:d=0.35,fade=out:st={OUTRO - 0.6}:d=0.6,setsar=1[out]")
    fc.append("[in][demo][out]concat=n=3:v=1:a=0[v]")
    fc.append(f"[{music_i}:a]atrim=0:{total:.3f},asetpts=PTS-STARTPTS,volume=0.8,"
              f"afade=in:st=0:d=0.6,afade=out:st={total - 2.0:.3f}:d=2.0[aud]")

    cmd = [FF, "-hide_banner", "-loglevel", "error", "-y", *inputs, "-filter_complex", ";".join(fc),
           "-map", "[v]", "-map", "[aud]", "-t", f"{total:.2f}", "-c:v", "libx264", "-crf", "19",
           "-preset", "slow", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k",
           "-movflags", "+faststart", OUT]
    subprocess.run(cmd, check=True)
    print("done", round(total, 2))


main()
