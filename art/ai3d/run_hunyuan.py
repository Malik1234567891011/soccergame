#!/usr/bin/env python3
"""Hunyuan3D-2.x via HF Space (gradio_client). Usage: run_hunyuan.py SPACE image.png out_prefix [octree_res] [steps]"""
import sys, time, shutil, json
from gradio_client import Client, handle_file
space, img, prefix = sys.argv[1], sys.argv[2], sys.argv[3]
octree = int(sys.argv[4]) if len(sys.argv) > 4 else 256
steps = int(sys.argv[5]) if len(sys.argv) > 5 else 30
c = Client(space, verbose=False)
t0 = time.time()
kw = dict(image=handle_file(img), steps=steps, guidance_scale=5.0, seed=1234, octree_resolution=octree,
          check_box_rembg=True, num_chunks=8000, randomize_seed=False, api_name="/generation_all")
if space == "tencent/Hunyuan3D-2": kw["caption"] = None
res = c.predict(**kw)
print("gen time", int(time.time()-t0), "s")
print(json.dumps(res[3])[:800] if len(res) > 3 else res)
shape, textured = res[0], res[1]
for src, tag in ((shape, "shape"), (textured, "textured")):
    p = src["value"] if isinstance(src, dict) else src
    ext = p.rsplit('.',1)[-1]
    shutil.copy(p, f"{prefix}_{tag}.{ext}"); print("saved", f"{prefix}_{tag}.{ext}")
