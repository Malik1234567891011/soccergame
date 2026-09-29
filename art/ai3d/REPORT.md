# AI image-to-3D test — LUNA (2026-09-29)

**Result:** geometry is usable (Hunyuan3D-2 shape: watertight, on-model silhouette, real braid, auto-rigs cleanly
at 20k tris). Texturing is the hard part: HF ZeroGPU anonymous quota blocked TRELLIS.2 / Hunyuan-2.1 textured runs,
Hunyuan-2 texture stage is broken server-side, Rodin trial key has no funds.

**Key finding:** projecting the gpt-image-1 model-sheet art onto the mesh looks *exactly* like the illustration from
the front / 3⁄4 (the "wow" target). Only sides/back fail with single-view projection → fix with multi-view
(front/back/left/right) gpt-image-1 *edits* of the same character, blended by surface normal.

Pipeline: gpt-image-1 edit (padded A-pose model sheet) → Hunyuan3D-2 `/shape_generation` (~10 s GPU, needs HF quota)
→ decimate ~20k → multi-view projection bake → auto-rig (hips/spine/chest/neck/head + limbs) → toon/unlit + outline in-engine.

Scripts here: make_ref.py, run_hy2_shape.py, run_trellis2.py, run_trellis1.py, run_hunyuan.py, run_rodin.py,
inspect_glb.py, render_views.py, autorig.py. Venv: `uv venv -p 3.12 /private/tmp/ai3dvenv && uv pip install gradio_client requests pillow numpy`.
Quota: a free HF token raises ZeroGPU limits; HF PRO ($9/mo) ≈ 25 GPU-min/day.
