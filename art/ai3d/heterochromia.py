"""Tripo bakes one iris colour for both eyes. Re-tint the blue iris inside a texture box crimson:
heterochromia.py <id> x0 y0 x1 y1  (texel box in Panna/Resources/Characters/<id>.jpg). Re-run after tripo_char.py."""
import sys, colorsys, numpy as np
from PIL import Image
i, (x0, y0, x1, y1) = sys.argv[1], map(int, sys.argv[2:6])
p = f'Panna/Resources/Characters/{i}.jpg'
a = np.asarray(Image.open(p).convert('RGB')).astype(np.float32) / 255
box = a[y0:y1, x0:x1]
mx = box.max(2); mn = box.min(2); sat = (mx - mn) / np.maximum(mx, 1e-6)
r, g, b = box[..., 0], box[..., 1], box[..., 2]
blue = (b >= g) & (b > r + 0.12) & (sat > 0.25)
# crimson with the same brightness ramp: v from the blue's max, a little extra saturation
v = mx[blue]; s = np.clip(sat[blue] * 1.1, 0, 1)
box[blue] = np.stack([v * 0.9, v * (1 - s * 0.95) * 0.45, v * (1 - s * 0.8) * 0.55], 1)
a[y0:y1, x0:x1] = box
Image.fromarray((a * 255).round().astype(np.uint8)).save(p, quality=92)
print('iris texels re-tinted', int(blue.sum()))
m = np.asarray(Image.open(f'Panna/Resources/Characters/{i}_mask.png').convert('L'))
print('kit-mask texels in box', int((m[y0:y1, x0:x1] > 10).sum()))
