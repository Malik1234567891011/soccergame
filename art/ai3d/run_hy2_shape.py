#!/usr/bin/env python3
"""tencent/Hunyuan3D-2 HF Space, SHAPE ONLY (the Space's texture stage currently throws NameError).
Usage: run_hy2_shape.py image.png out.glb   (optional env HF_TOKEN for more ZeroGPU quota)"""
import os, sys, time, json, httpx
from gradio_client import Client, handle_file
img, out = sys.argv[1], sys.argv[2]
tok = os.environ.get("HF_TOKEN")
if not tok:
    envp = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".env.local")
    tok = next((l.split("=", 1)[1].strip() for l in open(envp) if l.startswith("HF_TOKEN=")), None)
c = Client("tencent/Hunyuan3D-2", verbose=False, download_files=False, **({"token": tok} if tok else {}))
t0 = time.time()
r = c.predict(caption=None, image=handle_file(img), steps=30, guidance_scale=5.0, seed=1234, octree_resolution=256,
              check_box_rembg=True, num_chunks=8000, randomize_seed=False, api_name="/shape_generation")
print("gen", int(time.time()-t0), "s", json.dumps(r[2])[:300])
v = r[0]
if isinstance(v, dict) and "value" in v: v = v["value"]
url = v["url"] if isinstance(v, dict) else v
for i in range(6):  # the Space's file route 502s intermittently
    resp = httpx.get(url, timeout=120, headers={"Authorization": f"Bearer {tok}"} if tok else {})
    if resp.status_code == 200 and resp.content[:4] == b"glTF":
        open(out, "wb").write(resp.content); print("saved", out, len(resp.content)); break
    print("retry", resp.status_code); time.sleep(5)
