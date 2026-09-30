"""Square face portrait (head + collar) from a model sheet: look_portrait.py <id> [<id> ...]
Anchored on the body, not the hair: horizontal centre = the jersey's centre line, vertical = the collar.
(Hair buns, ponytails, ears and spikes used to pull the old top-of-silhouette crop off-centre.)"""
import sys, colorsys, numpy as np
from PIL import Image

def portrait(i):
    im = Image.open(f'{i}_ref_front.png').convert('RGB'); a = np.asarray(im).astype(np.float32) / 255
    bg = np.median(a[:10, :10].reshape(-1, 3), 0)
    fig = np.abs(a - bg).sum(2) > 0.16
    ys, xs = np.nonzero(fig); top, bot = ys.min(), ys.max(); H = bot - top
    mx = a.max(2); mn = a.min(2); sat = (mx - mn) / np.maximum(mx, 1e-6)
    r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    hue = np.zeros_like(mx); d = mx - mn; nz = d > 1e-6
    ir = nz & (mx == r); ig = nz & (mx == g) & ~ir; ib = nz & ~ir & ~ig
    hue[ir] = ((g - b)[ir] / d[ir]) % 6; hue[ig] = (b - r)[ig] / d[ig] + 2; hue[ib] = (r - g)[ib] / d[ib] + 4; hue /= 6
    # the code-kit jersey's yellow V collar: centre line and neck height in one
    yel = fig & (hue > 0.11) & (hue < 0.19) & (sat > 0.45) & (mx > 0.6)
    red = fig & ((hue < 0.03) | (hue > 0.96)) & (sat > 0.55) & (mx > 0.45)
    near_red = red.copy()
    for _ in range(4): near_red = near_red | np.roll(near_red, 1, 0) | np.roll(near_red, -1, 0) | np.roll(near_red, 1, 1) | np.roll(near_red, -1, 1)
    yel &= near_red                                   # collar trim borders the jersey; yellow hair doesn't
    ys_ = np.nonzero(yel[int(top + 0.08 * H):int(top + 0.4 * H)])
    if len(ys_[0]) > 30:
        yy = ys_[0] + int(top + 0.08 * H); xx = ys_[1]
        collar = int(np.percentile(yy, 3))                    # top of the collar = base of the neck
        near = yy < collar + 0.05 * H
        cx = float(np.median(xx[near]))
    else:
        cx = float(np.median(xs)); collar = int(top + 0.2 * H)
    s = 0.25 * H
    y0 = collar - 0.185 * H
    box = (int(cx - s / 2), int(y0), int(cx + s / 2), int(y0 + s))
    im.crop(box).resize((220, 220), Image.LANCZOS).save(f'../../Panna/Resources/Portraits/look_{i}.jpg', quality=90)
    print('portrait', i, 'cx %.0f collar %d' % (cx, collar))

for i in sys.argv[1:]: portrait(i)
