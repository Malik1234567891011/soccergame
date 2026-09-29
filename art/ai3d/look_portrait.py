"""Square face portrait (head + collar) from a model sheet: look_portrait.py <id>"""
import sys, numpy as np
from PIL import Image
i = sys.argv[1]
im = Image.open(f'{i}_ref_front.png').convert('RGB'); a = np.asarray(im).astype(int)
bg = np.median(a[:10, :10].reshape(-1, 3), 0)
m = np.abs(a - bg).sum(2) > 40
ys, xs = np.nonzero(m); top, bot = ys.min(), ys.max(); H = bot - top
band = m[top:int(top + 0.12 * H)]; bx = np.nonzero(band.any(0))[0]; cx = (bx.min() + bx.max()) / 2
s = 0.24 * H
box = (int(cx - s / 2), int(top - 0.02 * H), int(cx + s / 2), int(top - 0.02 * H + s))
im.crop(box).resize((220, 220), Image.LANCZOS).save(f'../../Panna/Resources/Portraits/look_{i}.jpg', quality=90)
print('portrait', i)
