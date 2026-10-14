"""アプリアイコン（1024x1024）を作る：紙の地に、下がギザギザのレシートと朱色の ¥"""
import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

S = 1024
PAPER = (244, 241, 234)
CARD = (255, 254, 251)
INK = (26, 25, 24)
FAINT = (200, 194, 183)
ACCENT = (217, 62, 41)

img = Image.new("RGB", (S, S), ACCENT)
d = ImageDraw.Draw(img)

# レシート
w, h = 560, 700
x0, y0 = (S - w) // 2, 150
x1, y1 = x0 + w, y0 + h
teeth = 9
tooth = w / teeth
depth = 34
pts = [(x0, y0), (x1, y0), (x1, y1)]
for i in range(teeth):
    xa = x1 - i * tooth
    pts.append((xa - tooth / 2, y1 - depth))
    pts.append((xa - tooth, y1))
shadow = Image.new("L", (S, S), 0)
ImageDraw.Draw(shadow).polygon([(x + 0, y + 22) for x, y in pts], fill=110)
shadow = shadow.filter(ImageFilter.GaussianBlur(26))
img.paste((120, 30, 20), (0, 0), shadow)
d = ImageDraw.Draw(img)
d.polygon(pts, fill=CARD)

# 明細の行
pad = 70
for i, (lw, rw) in enumerate([(230, 90), (170, 120), (260, 70)]):
    y = y0 + 90 + i * 62
    d.rounded_rectangle((x0 + pad, y, x0 + pad + lw, y + 22), 11, fill=FAINT)
    d.rounded_rectangle((x1 - pad - rw, y, x1 - pad, y + 22), 11, fill=FAINT)
# 点線
yd = y0 + 300
x = x0 + pad
while x < x1 - pad:
    d.rectangle((x, yd, x + 18, yd + 6), fill=FAINT)
    x += 34

font = None
for path in ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf"]:
    try:
        font = ImageFont.truetype(path, 300)
        break
    except OSError:
        pass
if font is None:
    font = ImageFont.load_default()
text = "¥"
bbox = d.textbbox((0, 0), text, font=font)
tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
d.text(((S - tw) / 2 - bbox[0], yd + 40 - bbox[1] + (y1 - depth - yd - 40 - th) / 2 - 10), text, font=font, fill=INK)

img.save(sys.argv[1] if len(sys.argv) > 1 else "AppIcon.png")
