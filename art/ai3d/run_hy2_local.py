#!/usr/bin/env python3
"""Hunyuan3D-2mini shape generation on this Mac (Apple GPU) — fallback when the HF Space quota is spent.
Usage: /private/tmp/hyvenv/bin/python run_hy2_local.py image.png out.glb   (needs /private/tmp/Hunyuan3D-2 on sys.path)"""
import sys, time, torch
sys.path.insert(0, '/private/tmp/Hunyuan3D-2'); sys.path.insert(0, '/private/tmp/hystubs')
from PIL import Image
from hy3dgen.rembg import BackgroundRemover
from hy3dgen.shapegen import Hunyuan3DDiTFlowMatchingPipeline
pairs = list(zip(sys.argv[1::2], sys.argv[2::2]))   # img out [img out ...]
dev = 'mps' if torch.backends.mps.is_available() else 'cpu'
t0 = time.time()
pipe = Hunyuan3DDiTFlowMatchingPipeline.from_pretrained('tencent/Hunyuan3D-2mini', subfolder='hunyuan3d-dit-v2-mini', use_safetensors=True, device=dev)
rm = BackgroundRemover()
for img, out in pairs:
    im = rm(Image.open(img).convert('RGB'))
    mesh = pipe(image=im, num_inference_steps=30, octree_resolution=256, num_chunks=8000, generator=torch.manual_seed(1234), output_type='trimesh')[0]
    mesh.export(out)
    print('saved', out, len(mesh.faces), 'faces', int(time.time() - t0), 's', flush=True)
