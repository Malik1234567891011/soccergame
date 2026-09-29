#!/usr/bin/env python3
"""Pick the Prospect mesh whose front silhouette best matches a roster look's front sheet (IoU of normalised masks)."""
import sys, numpy as np
from PIL import Image
def mask(path):
    a = np.asarray(Image.open(path).convert('RGB')).astype(np.float32) / 255
    bg = np.median(np.concatenate([a[:8, :8].reshape(-1, 3), a[-8:, -8:].reshape(-1, 3)]), axis=0)
    m = np.abs(a - bg).sum(axis=2) > 0.12
    ys, xs = np.nonzero(m)
    crop = m[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    h = crop.shape[0]
    # Normalise by height only (keep width proportions), centre horizontally in a fixed canvas.
    img = Image.fromarray((crop * 255).astype(np.uint8)).resize((max(1, int(crop.shape[1] * 400 / h)), 400))
    canvas = Image.new('L', (400, 400)); canvas.paste(img, ((400 - img.size[0]) // 2, 0))
    return np.asarray(canvas) > 127
target = mask(sys.argv[1])
best = None
for cand in sys.argv[2:]:
    m = mask(cand)
    # Weight the head region (top 25%) double: hair volume matters most.
    iou = (target & m).sum() / max(1, (target | m).sum())
    hh = (target[:100] & m[:100]).sum() / max(1, (target[:100] | m[:100]).sum())
    score = iou + hh
    if best is None or score > best[0]: best = (score, cand)
print(best[1])
