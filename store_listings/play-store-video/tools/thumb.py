"""YouTube thumbnail (1280x720) from the Play feature graphic (1024x500).

The feature graphic is only resized (never edited or replaced): scaled to
1280 wide, centred on a blurred copy of itself so the 16:9 frame's extra
height continues the art's own colours, with feathered top/bottom edges.
Usage (from the Flutter app root): python -I store_listings/play-store-video/tools/thumb.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[3]
SRC = ROOT / "play-store-screenshots" / "feature-graphic-1024x500.png"
OUT = ROOT / "store_listings" / "play-store-video" / "youtube-thumbnail-1280x720.png"
W, H = 1280, 720
FEATHER = 60

src = Image.open(SRC).convert("RGB")
scaled = src.resize((W, round(src.height * W / src.width)), Image.LANCZOS)  # 1280x625
top = (H - scaled.height) // 2

base = scaled.filter(ImageFilter.GaussianBlur(80)).resize((W, H), Image.LANCZOS)
base = Image.blend(base, Image.new("RGB", (W, H), (10, 10, 13)), 0.35)  # Prism Noir canvas

mask = Image.new("L", scaled.size, 255)
md = ImageDraw.Draw(mask)
for i in range(FEATHER):
    a = round(255 * (i / FEATHER) ** 1.4)
    md.line([(0, i), (W, i)], fill=a)
    md.line([(0, scaled.height - 1 - i), (W, scaled.height - 1 - i)], fill=a)
base.paste(scaled, (0, top), mask)
base.save(OUT, optimize=True)
print(OUT, base.size)
