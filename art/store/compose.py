"""App Store screenshots (landscape 2796x1290, iPhone 6.9"). python compose.py → out/01..06.png"""
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageEnhance

W, H = 2796, 1290
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..', '..')
OUT = os.path.join(HERE, 'out'); os.makedirs(OUT, exist_ok=True)
FONT = '/System/Library/Fonts/Avenir Next Condensed.ttc'
def font(size, idx=9): return ImageFont.truetype(FONT, size, index=idx)
PINK, GREEN, GOLD, CYAN = (255, 59, 92), (57, 255, 136), (255, 210, 59), (59, 232, 255)

def cover(img, w, h, focus_x=0.5):
    s = max(w / img.width, h / img.height)
    im = img.resize((int(img.width * s + 1), int(img.height * s + 1)), Image.LANCZOS)
    x = int((im.width - w) * focus_x); y = (im.height - h) // 2
    return im.crop((x, y, x + w, y + h))

def left_shade(im, frac=0.55, strength=235):
    g = Image.new('L', (W, 1))
    for x in range(W):
        t = max(0.0, 1 - x / (W * frac))
        g.putpixel((x, 0), int(strength * (t ** 1.3)))
    g = g.resize((W, H))
    dark = Image.new('RGB', (W, H), (8, 9, 20))
    return Image.composite(dark, im, g)

def bottom_shade(im, strength=160):
    g = Image.new('L', (1, H))
    for y in range(H): g.putpixel((0, y), int(strength * max(0, (y / H - 0.55) / 0.45) ** 1.5))
    return Image.composite(Image.new('RGB', (W, H), (8, 9, 20)), im, g.resize((W, H)))

def title(im, lines, x=150, y=330, size=190, colors=None, sub=None, sub_color=(230, 232, 245), tag=None, tag_color=PINK):
    d = ImageDraw.Draw(im)
    if tag:
        f = font(54, 8)
        tw = d.textlength(tag, font=f)
        d.polygon([(x, y - 120), (x + tw + 70, y - 120), (x + tw + 50, y - 50), (x - 20, y - 50)], fill=tag_color)
        d.text((x + 22, y - 116), tag, font=f, fill=(10, 10, 16))
    f = font(size)
    yy = y
    for i, ln in enumerate(lines):
        c = (colors or [(255, 255, 255)] * len(lines))[i]
        # chunky offset shadow like the in-game logo
        d.text((x + 10, yy + 12), ln, font=f, fill=(0, 0, 0))
        d.text((x, yy), ln, font=f, fill=c)
        yy += int(size * 0.98)
    if sub:
        d.text((x + 6, yy + 30), sub, font=font(64, 6), fill=sub_color)
    return im

def rounded(img, r):
    m = Image.new('L', img.size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, img.width, img.height), r, fill=255)
    out = Image.new('RGBA', img.size); out.paste(img, (0, 0), m); return out

def glow_paste(base, card, pos, color, blur=40, spread=1.0):
    gl = Image.new('RGBA', (card.width + 200, card.height + 200), (0, 0, 0, 0))
    ImageDraw.Draw(gl).rounded_rectangle((100, 100, 100 + card.width, 100 + card.height), 40, fill=color + (int(200 * spread),))
    gl = gl.filter(ImageFilter.GaussianBlur(blur))
    base.paste(gl, (pos[0] - 100, pos[1] - 100), gl)
    base.paste(card, pos, card)

def load(p): return Image.open(os.path.join(ROOT, p)).convert('RGB')

# 1 — hero
im = cover(Image.open(os.path.join(HERE, 'bg_hero.png')).convert('RGB'), W, H, 0.62)
im = left_shade(im, 0.6)
title(im, ['NUTMEG', 'YOUR', 'FRIENDS.'], y=300, size=200, colors=[(255, 255, 255), (255, 255, 255), GREEN],
      sub='3v3 street football · Skills · Rivals', tag='PANNA')
im.save(os.path.join(OUT, '01_hero.png'))

# 2 — collect legends: real card art fanned out
bg = cover(Image.open(os.path.join(HERE, 'bg_flow.png')).convert('RGB'), W, H, 0.5).filter(ImageFilter.GaussianBlur(28))
bg = ImageEnhance.Brightness(bg).enhance(0.45)
im = left_shade(bg, 0.5, 200).convert('RGBA')
cards = ['l31', 'l27', 'l30', 'l17', 'l23', 'l26', 'l20']
rar = {'l31': GOLD, 'l30': GOLD, 'l27': CYAN, 'l17': (178, 107, 255), 'l23': (178, 107, 255), 'l26': (178, 107, 255), 'l20': (178, 107, 255)}
cw, ch = 380, 570
xs = [1080 + i * 205 for i in range(len(cards))]
order = [0, 6, 1, 5, 2, 4, 3]   # draw outer cards first, centre last (on top)
for k in order:
    c = cards[k]
    card = load(f'Panna/Resources/Portraits/lookcard_{c}.jpg').resize((cw, ch), Image.LANCZOS)
    card = rounded(card, 34)
    frame = Image.new('RGBA', (cw + 16, ch + 16), (0, 0, 0, 0))
    ImageDraw.Draw(frame).rounded_rectangle((0, 0, cw + 15, ch + 15), 40, fill=rar[c] + (255,))
    frame.paste(card, (8, 8), card)
    ang = (k - 3) * -6
    fr = frame.rotate(ang, expand=True, resample=Image.BICUBIC)
    y = 360 + abs(k - 3) * 40 - (60 if k == 3 else 0)
    glow_paste(im, fr, (xs[k] - fr.width // 2 + 200, y - 120), rar[c], blur=45, spread=0.6)
im = im.convert('RGB')
title(im, ['COLLECT', 'STREET', 'LEGENDS'], y=300, size=190, colors=[(255, 255, 255), GOLD, (255, 255, 255)],
      sub='40+ footballers · Common to Legendary', tag='SQUAD')
im.save(os.path.join(OUT, '02_collect.png'))

# 3 — real gameplay, framed
shot = Image.open(os.path.join(HERE, 'raw_paris_1.png')).convert('RGB')
shot = shot.crop((150, 0, shot.width - 60, shot.height))
bg = cover(Image.open(os.path.join(HERE, 'bg_hero.png')).convert('RGB'), W, H, 0.5).filter(ImageFilter.GaussianBlur(30))
im = ImageEnhance.Brightness(bg).enhance(0.35).convert('RGBA')
sw = 1660; shf = shot.resize((sw, int(shot.height * sw / shot.width)), Image.LANCZOS)
dev = Image.new('RGBA', (shf.width + 44, shf.height + 44), (0, 0, 0, 0))
ImageDraw.Draw(dev).rounded_rectangle((0, 0, dev.width - 1, dev.height - 1), 70, fill=(14, 15, 22, 255))
dev.paste(rounded(shf, 52), (22, 22), rounded(shf, 52))
dev = dev.rotate(-4, expand=True, resample=Image.BICUBIC)
glow_paste(im, dev, (W - dev.width - 70, (H - dev.height) // 2 + 10), CYAN, blur=60, spread=0.5)
im = im.convert('RGB')
title(im, ['REAL', '3V3', 'FOOTBALL'], x=120, y=330, size=180, colors=[(255, 255, 255), CYAN, (255, 255, 255)],
      sub='Skills · Pannas · Bicycle kicks', tag='GAMEPLAY', tag_color=CYAN)
im.save(os.path.join(OUT, '03_gameplay.png'))

# 4 — friends / private rooms
im = cover(Image.open(os.path.join(HERE, 'bg_rivals.png')).convert('RGB'), W, H, 0.7)
im = left_shade(im, 0.6)
d = ImageDraw.Draw(im)
title(im, ['PLAY', 'YOUR', 'FRIENDS'], y=280, size=200, colors=[(255, 255, 255), (255, 255, 255), PINK],
      sub='Private rooms · Send a code · Rematch', tag='ONLINE', tag_color=GREEN)
# room-code chip
cx, cy = 156, 1040
d.rounded_rectangle((cx, cy, cx + 640, cy + 150), 30, fill=(20, 22, 36), outline=CYAN, width=4)
d.text((cx + 36, cy + 34), 'ROOM', font=font(52, 8), fill=(160, 165, 190))
d.text((cx + 230, cy + 8), '2RPG', font=font(118, 9), fill=GOLD)
im.save(os.path.join(OUT, '04_friends.png'))

# 5 — flow
im = cover(Image.open(os.path.join(HERE, 'bg_flow.png')).convert('RGB'), W, H, 0.6)
im = left_shade(im, 0.58)
title(im, ['UNLEASH', 'YOUR', 'FLOW'], y=300, size=210, colors=[(255, 255, 255), (255, 255, 255), GOLD],
      sub='Five weapons. Five supers. Your style.', tag='SUPER MODE', tag_color=GOLD)
im.save(os.path.join(OUT, '05_flow.png'))

# 6 — legend / squad: real locker screen + three cards
bg = cover(Image.open(os.path.join(HERE, 'bg_rivals.png')).convert('RGB'), W, H, 0.3).filter(ImageFilter.GaussianBlur(30))
im = ImageEnhance.Brightness(bg).enhance(0.35).convert('RGBA')
lk = Image.open(os.path.join(HERE, 'raw_locker.png')).convert('RGB')
lk = lk.crop((150, 0, lk.width - 60, lk.height))
sw = 1500; lkf = lk.resize((sw, int(lk.height * sw / lk.width)), Image.LANCZOS)
dev = Image.new('RGBA', (lkf.width + 40, lkf.height + 40), (0, 0, 0, 0))
ImageDraw.Draw(dev).rounded_rectangle((0, 0, dev.width - 1, dev.height - 1), 64, fill=(14, 15, 22, 255))
dev.paste(rounded(lkf, 48), (20, 20), rounded(lkf, 48))
glow_paste(im, dev, (W - dev.width - 90, (H - dev.height) // 2), PINK, blur=60, spread=0.45)
im = im.convert('RGB')
title(im, ['BUILD', 'YOUR', 'LEGEND'], x=120, y=330, size=190, colors=[(255, 255, 255), (255, 255, 255), GREEN],
      sub='Looks · Kits · Moves · Celebrations', tag='LOCKER', tag_color=GREEN)
im.save(os.path.join(OUT, '06_legend.png'))
print('done')
