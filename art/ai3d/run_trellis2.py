#!/usr/bin/env python3
"""microsoft/TRELLIS.2 HF Space image-to-3D -> textured GLB.
Usage: run_trellis2.py image.png out.glb [resolution 512|1024|1536] [decimation_target] [texture_size]"""
import sys, time, shutil
from gradio_client import Client, handle_file
img, out = sys.argv[1], sys.argv[2]
res = sys.argv[3] if len(sys.argv) > 3 else "1024"
dec = int(sys.argv[4]) if len(sys.argv) > 4 else 200000
tex = int(sys.argv[5]) if len(sys.argv) > 5 else 2048
import os
tok = next((l.split("=", 1)[1].strip() for l in open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".env.local")) if l.startswith("HF_TOKEN=")), None)
c = Client("microsoft/TRELLIS.2", verbose=False, token=tok)
t0 = time.time()
try: c.predict(api_name="/start_session")
except Exception as e: print("start_session:", e)
pre = c.predict(handle_file(img), api_name="/preprocess_image")
print("preprocessed", int(time.time()-t0), "s", pre)
shutil.copy(pre["path"] if isinstance(pre, dict) else pre, out.replace('.glb', '_preproc.png'))
c.predict(handle_file(pre["path"] if isinstance(pre, dict) else pre), 0, res, api_name="/image_to_3d")
print("image_to_3d done", int(time.time()-t0), "s", flush=True)
glb = c.predict(dec, tex, api_name="/extract_glb")
print("extract done", int(time.time()-t0), "s", glb)
p = glb[1] if isinstance(glb, (list, tuple)) else glb
p = p["value"] if isinstance(p, dict) and "value" in p else (p["path"] if isinstance(p, dict) else p)
shutil.copy(p, out); print("saved", out)
