#!/usr/bin/env python3
"""trellis-community/TRELLIS (v1) HF Space -> textured GLB. Usage: run_trellis1.py image.png out.glb"""
import sys, time, shutil
from gradio_client import Client, handle_file
img, out = sys.argv[1], sys.argv[2]
c = Client("trellis-community/TRELLIS", verbose=False); t0 = time.time()
try: c.predict(api_name="/start_session")
except Exception as e: print("start_session:", e)
pre = c.predict(handle_file(img), api_name="/preprocess_image")
r = c.predict(image=handle_file(pre["path"] if isinstance(pre, dict) else pre), multiimages=[], seed=0,
              ss_guidance_strength=7.5, ss_sampling_steps=12, slat_guidance_strength=3.0, slat_sampling_steps=12,
              multiimage_algo="stochastic", mesh_simplify=0.95, texture_size=1024, api_name="/generate_and_extract_glb")
print("t", int(time.time()-t0), r)
p = r[2] if isinstance(r[2], str) else r[2].get("value") or r[2].get("path")
shutil.copy(p, out); print("saved", out)
