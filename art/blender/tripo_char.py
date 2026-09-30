"""
Tripo character importer: a fully textured game-asset model (Tripo Studio / API) → rigged PANNA character.
No projection or guessing: the model is already painted all the way round. We only normalise, rig, and export.
  Blender -b -P art/blender/tripo_char.py -- --mesh luna_tripo.glb --name luna [--tris 20000] [--preview]
Output: Panna/Resources/Characters/<name>.bin / .jpg / _mask.png / _kit.json (same formats as unique.py)
"""
import bpy, bmesh, math, json, sys, os, struct, colorsys, subprocess
import numpy as np
from mathutils import Vector, Matrix

A = sys.argv[sys.argv.index('--') + 1:]
def arg(k, d=None): return A[A.index(k) + 1] if k in A else d
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
NAME = arg('--name', 'unique')
HEIGHT = float(arg('--height', '1.9'))
TRIS = int(arg('--tris', '20000'))
OUT = os.path.join(ROOT, 'Panna', 'Resources', 'Characters')

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

# ------------------------------------------------------------------ import + normalise
bpy.ops.import_scene.gltf(filepath=os.path.abspath(arg('--mesh')), merge_vertices=True)
meshes = [o for o in scene.objects if o.type == 'MESH']
for o in scene.objects: o.select_set(o in meshes)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1: bpy.ops.object.join()
obj = bpy.context.active_object
obj.parent = None
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in list(scene.objects):
    if o != obj: bpy.data.objects.remove(o)

def bbox(o):
    c = np.array([v.co[:] for v in o.data.vertices])
    return Vector(c.min(0)), Vector(c.max(0))
# Orientation: studio viewer GLBs and exports differ. Put the arm span on X, then face -Y (boot toes point forward).
_c = np.array([v.co[:] for v in obj.data.vertices]); _z0, _z1 = _c[:, 2].min(), _c[:, 2].max(); _h = _z1 - _z0
_band = _c[(_c[:, 2] > _z0 + 0.55 * _h) & (_c[:, 2] < _z0 + 0.75 * _h)]
if np.ptp(_band[:, 1]) > np.ptp(_band[:, 0]) * 1.15:
    obj.data.transform(Matrix.Rotation(math.radians(-90), 4, 'Z')); _c = np.array([v.co[:] for v in obj.data.vertices])
toes = _c[_c[:, 2] < _z0 + 0.02 * _h, 1].mean(); ankles = _c[(_c[:, 2] > _z0 + 0.05 * _h) & (_c[:, 2] < _z0 + 0.09 * _h), 1].mean()
if toes > ankles:
    obj.data.transform(Matrix.Rotation(math.radians(180), 4, 'Z'))
print('TRIPO orient: toes-ankles %.3f' % (toes - ankles))
mn, mx = bbox(obj)
s = HEIGHT / (mx.z - mn.z)
ctr = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))
for v in obj.data.vertices: v.co = (v.co - ctr) * s
n0 = len(obj.data.polygons)
if n0 > TRIS * 1.05:
    dec = obj.modifiers.new('dec', 'DECIMATE'); dec.ratio = TRIS / n0
    bpy.ops.object.modifier_apply(modifier='dec')
for p in obj.data.polygons: p.use_smooth = True
mn, mx = bbox(obj); H = mx.z - mn.z
print('TRIPO mesh', n0, '->', len(obj.data.polygons), 'faces; bbox', tuple(mn), tuple(mx))

# ------------------------------------------------------------------ hidden inner layers
# Generated meshes carry a body shell under the kit. When the two layers bend by slightly different amounts the
# inner one pokes through as jagged dark tears, so delete faces that an outer layer fully covers (below the head).
from mathutils.bvhtree import BVHTree
bm = bmesh.new(); bm.from_mesh(obj.data); bm.faces.ensure_lookup_table()
tree = BVHTree.FromBMesh(bm)
hid = []
for f in bm.faces:
    c = f.calc_center_median()
    if c.z > mn.z + 0.83 * H: continue
    nrm = f.normal
    if nrm.length < 0.5: continue
    covered = True
    for o_ in (Vector((0, 0, 0)), (f.verts[0].co - c) * 0.8, (f.verts[1].co - c) * 0.8):
        loc, hn, idx, dist = tree.ray_cast(c + o_ + nrm * 0.0015 * H, nrm, 0.008 * H)   # a skin-tight layer, never a limb
        if idx is None or idx == f.index or hn.dot(nrm) < 0.7: covered = False; break
    if covered: hid.append(f)
bmesh.ops.delete(bm, geom=hid, context='FACES')
bm.to_mesh(obj.data); bm.free()
print('TRIPO hidden faces removed', len(hid), 'of', n0 if False else len(obj.data.polygons) + len(hid))
mn, mx = bbox(obj); H = mx.z - mn.z

# ------------------------------------------------------------------ texture (the model's own base colour)
def base_image(mat):
    if not mat or not mat.use_nodes: return None
    for n in mat.node_tree.nodes:
        if n.type == 'BSDF_PRINCIPLED':
            l = n.inputs['Base Color'].links
            if l and l[0].from_node.type == 'TEX_IMAGE': return l[0].from_node.image
    for n in mat.node_tree.nodes:
        if n.type == 'TEX_IMAGE': return n.image
    return None
imgs = [base_image(m) for m in obj.data.materials]
imgs = [i for i in imgs if i]
assert imgs, 'no base colour texture in the model'
if len(set(i.name for i in imgs)) > 1:
    # Several texture sets: bake them into one atlas on fresh UVs.
    bpy.context.view_layer.objects.active = obj
    uvn = obj.data.uv_layers.new(name='atlas')
    obj.data.uv_layers.active = uvn
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.003)
    bpy.ops.object.mode_set(mode='OBJECT')
    atlas = bpy.data.images.new('atlas', 2048, 2048)
    for m in obj.data.materials:
        t = m.node_tree.nodes.new('ShaderNodeTexImage'); t.image = atlas; m.node_tree.nodes.active = t
    scene.render.engine = 'CYCLES'; scene.cycles.samples = 1
    scene.render.bake.use_pass_direct = False; scene.render.bake.use_pass_indirect = False
    bpy.ops.object.bake(type='DIFFUSE', uv_layer='atlas')
    for u in list(obj.data.uv_layers):
        if u.name != 'atlas': obj.data.uv_layers.remove(u)
    tex = atlas
else:
    tex = imgs[0]
    for u in list(obj.data.uv_layers)[1:]: obj.data.uv_layers.remove(u)
T = tex.size[0]
tpx = np.array(tex.pixels[:], dtype=np.float32).reshape(tex.size[1], tex.size[0], 4)[:, :, :3]   # linear, bottom-up
tex_srgb = np.where(tpx <= 0.0031308, tpx * 12.92, 1.055 * np.power(np.clip(tpx, 0, 1), 1 / 2.4) - 0.055) if tex.colorspace_settings.name != 'Non-Color' else tpx
tex_path = os.path.join(OUT, NAME + '.png')
Image_out = bpy.data.images.new('out', tex.size[0], tex.size[1])
Image_out.pixels[:] = np.dstack([tpx, np.ones(tpx.shape[:2], np.float32)]).ravel()
Image_out.filepath_raw = tex_path; Image_out.file_format = 'PNG'; Image_out.save()
jpg = tex_path[:-4] + '.jpg'
subprocess.run(['sips', '-s', 'format', 'jpeg', '-s', 'formatOptions', '90', '-Z', '2048', tex_path, '--out', jpg], capture_output=True)
os.remove(tex_path)
print('TRIPO texture', jpg, tex.size[:])

# ------------------------------------------------------------------ rig (same skeleton as every PANNA character)
vs = np.array([v.co[:] for v in obj.data.vertices])
def slab(z0, z1): return vs[(vs[:, 2] >= z0) & (vs[:, 2] <= z1)]
def depth_at(x, z, r=0.06):
    m = (np.abs(vs[:, 2] - z) < r) & (np.abs(vs[:, 0] - x) < r)
    return float(vs[m, 1].mean()) if m.any() else 0.0
Zf = lambda f: mn.z + f * H
cs = slab(Zf(0.70), Zf(0.74))
torso_hw = float(np.sort(np.abs(cs[:, 0]))[int(len(cs) * 0.6)]) if len(cs) else 0.15 * H
armband = slab(Zf(0.40), Zf(0.80))
def J(x, z): return Vector((x, depth_at(x, z), z))
arm = bpy.data.armatures.new('rig')
ro = bpy.data.objects.new('rig', arm); scene.collection.objects.link(ro)
bpy.ops.object.select_all(action='DESELECT'); bpy.context.view_layer.objects.active = ro; ro.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
eb = arm.edit_bones
def bone(name, h, t, parent=None):
    b = eb.new(name); b.head, b.tail = h, t
    if parent: b.parent = eb[parent]; b.use_connect = False
bone('hips', J(0, Zf(0.50)), J(0, Zf(0.58)))
bone('spine', J(0, Zf(0.58)), J(0, Zf(0.67)), 'hips')
bone('chest', J(0, Zf(0.67)), J(0, Zf(0.79)), 'spine')
bone('neck', J(0, Zf(0.79)), J(0, Zf(0.83)), 'chest')
bone('head', J(0, Zf(0.83)), J(0, Zf(1.0)), 'neck')
# Arms: walk down in thin horizontal slabs; the arm is the outermost cross-section that is its own connected piece
# (separated from the torso by a gap). That traces the real arm centreline even when a hand rests on the shorts.
CELL = 0.013 * H
def comps(pts):
    keys = {}
    for i, (x, y) in enumerate(pts[:, :2]): keys.setdefault((int(math.floor(x / CELL)), int(math.floor(y / CELL))), []).append(i)
    seen, out = set(), []
    for k in keys:
        if k in seen: continue
        stack, idx = [k], []; seen.add(k)
        while stack:
            c = stack.pop(); idx += keys[c]
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    nb = (c[0] + dx, c[1] + dy)
                    if nb in keys and nb not in seen: seen.add(nb); stack.append(nb)
        out.append(np.array(idx))
    return out
# torso half-width: the connected piece through the middle at waist height (arms hang free there)
_m = (vs[:, 2] > Zf(0.60)) & (vs[:, 2] < Zf(0.64)); _sl = vs[_m]
if len(_sl) > 20:
    _c = min(comps(_sl), key=lambda c: np.abs(_sl[c, 0]).min())
    torso_hw = float(np.percentile(np.abs(_sl[_c, 0]), 97))
print('TRIPO torso_hw %.3f H' % (torso_hw / H))
arm_label = np.zeros(len(vs), dtype=np.int8)   # +1 left arm, -1 right arm
arm_track = {1: [], -1: []}
arm_seeds = {1: np.zeros(0, int), -1: np.zeros(0, int)}
cands = {1: [], -1: []}
zs = np.arange(Zf(0.80), Zf(0.28), -0.5 * CELL)
for z in zs:
    m = (vs[:, 2] >= z - 0.5 * CELL) & (vs[:, 2] < z + 0.5 * CELL)
    sl = vs[m]; si = np.where(m)[0]
    per = {1: [], -1: []}
    if len(sl) >= 5:
        for c in comps(sl):
            if len(c) < 3: continue                                     # stray cloth shell fragments
            xs = sl[c, 0]; sgn = 1 if xs.mean() > 0 else -1
            if (xs * sgn).min() < 0.045 * H: continue                    # reaches the midline: torso / pelvis
            ctr_ = sl[c, :2].mean(0)
            rad = float(np.percentile(np.linalg.norm(sl[c, :2] - ctr_, axis=1), 90))
            per[sgn].append((float(ctr_[0]), float(ctr_[1]), float(z), rad, si[c]))
    for sgn in (1, -1):
        # a sparse forearm slab can split into inner/outer surface pieces: merge pieces within an arm's width
        ps = sorted(per[sgn], key=lambda q: q[0] * sgn)
        merged = []
        for q in ps:
            if merged and min(len(q[4]), len(merged[-1][4])) <= 12 and abs(q[0] - merged[-1][0]) < 0.08 * H and abs(q[1] - merged[-1][1]) < 0.07 * H:
                ii = np.concatenate([merged[-1][4], q[4]]); pts_ = vs[ii, :2]; ctr_ = pts_.mean(0)
                merged[-1] = (float(ctr_[0]), float(ctr_[1]), q[2], float(np.percentile(np.linalg.norm(pts_ - ctr_, axis=1), 90)), ii)
            else: merged.append(q)
        cands[sgn].append(merged)
if '--armdbg' in A:
    for zi, z in enumerate(zs):
        if Zf(0.36) < z < Zf(0.56): print('  cand z %.3f' % ((z - mn.z) / H), [('%.3f' % (q[0] / H), '%.3f' % (q[1] / H), len(q[4])) for q in cands[1][zi]])
# Legs: follow each leg up from the ankle; an 'arm' section that coincides with a leg section is thigh/shorts.
leg_at = {}
for sgn in (1, -1):
    prev = None
    for zi in range(len(zs) - 1, -1, -1):
        z = zs[zi]
        if z < Zf(0.08) or z > Zf(0.50): continue
        m = (vs[:, 2] >= z - 0.5 * CELL) & (vs[:, 2] < z + 0.5 * CELL); sl = vs[m]
        if len(sl) < 5: continue
        best_ = None
        for c in comps(sl):
            if len(c) < 6: continue
            ctr_ = sl[c, :2].mean(0)
            if ctr_[0] * sgn <= 0: continue
            d_ = abs(ctr_[0] - prev[0]) + abs(ctr_[1] - prev[1]) if prev is not None else -len(c)
            if prev is not None and d_ > 0.06 * H: continue
            if best_ is None or d_ < best_[0]: best_ = (d_, ctr_, float(np.percentile(np.linalg.norm(sl[c, :2] - ctr_, axis=1), 95)))
        if best_ is not None:
            prev = best_[1]; leg_at[(sgn, zi)] = (best_[1], best_[2])
# a hand resting on the shorts merges into the 'leg' section: clamp each leg to its thigh's own centre and radius
for sgn in (1, -1):
    ref = [v_ for (s_, zi_), v_ in leg_at.items() if s_ == sgn and Zf(0.2) < zs[zi_] < Zf(0.33)]
    if not ref: continue
    cx_ = np.median([c[0][0] for c in ref]); cy_ = np.median([c[0][1] for c in ref]); rr_ = np.median([c[1] for c in ref])
    for k_ in [k for k in leg_at if k[0] == sgn]:
        c_, r_ = leg_at[k_]
        c_ = np.array([np.clip(c_[0], cx_ - 0.02 * H, cx_ + 0.02 * H), np.clip(c_[1], cy_ - 0.03 * H, cy_ + 0.03 * H)])
        leg_at[k_] = (c_, min(r_, rr_ * 1.25))
# torso silhouette: per slab, the half-width of the cross-section piece that crosses the midline
_tz, _tw = [], []
for z in zs:
    m_ = (vs[:, 2] >= z - 0.5 * CELL) & (vs[:, 2] < z + 0.5 * CELL); sl_ = vs[m_]
    if len(sl_) < 8: continue
    mid = [c for c in comps(sl_) if np.abs(sl_[c, 0]).min() < 0.02 * H]
    if mid:
        c = max(mid, key=len); _tz.append(z); _tw.append(float(np.percentile(np.abs(sl_[c, 0]), 95)))
_tz = np.array(_tz[::-1]); _tw = np.array(_tw[::-1])
def torso_edge(z): return np.interp(z, _tz, _tw) if len(_tz) else 0.12 * H
leg_mask = np.zeros(len(vs), bool)
# code-kit shorts are blue: a fused hand must never grow into shorts-coloured surface
_uvl = obj.data.uv_layers.active.data; _vuv = np.zeros((len(vs), 2))
for l_ in obj.data.loops: _vuv[l_.vertex_index] = _uvl[l_.index].uv
_ty, _tx = tex_srgb.shape[:2]
_px = tex_srgb[np.clip((_vuv[:, 1] * _ty).astype(int), 0, _ty - 1), np.clip((_vuv[:, 0] * _tx).astype(int), 0, _tx - 1)]
_mx = _px.max(1); _mn = _px.min(1); _sat = (_mx - _mn) / np.maximum(_mx, 1e-6)
_hue = np.array([colorsys.rgb_to_hsv(*c)[0] for c in _px])
shorts_px = (np.minimum(np.abs(_hue - 0.62), 1 - np.abs(_hue - 0.62)) < 0.07) & (_sat > 0.3) & (_mx > 0.12) & (vs[:, 2] < Zf(0.56))
leg_mask |= shorts_px
print('TRIPO shorts-blue verts', int(shorts_px.sum()))
for (sgn_, zi_), (c_, r_) in leg_at.items():
    z_ = zs[zi_]; m_ = (vs[:, 2] >= z_ - 0.5 * CELL) & (vs[:, 2] < z_ + 0.5 * CELL)
    leg_mask[np.where(m_)[0][np.hypot(vs[m_, 0] - c_[0], vs[m_, 1] - c_[1]) < r_ + 0.004 * H]] = True
def on_leg(q, zi):
    for sgn in (1, -1):
        l_ = leg_at.get((sgn, zi))
        if l_ is not None and math.hypot(q[0] - l_[0][0], q[1] - l_[0][1]) < l_[1] + 0.005 * H: return True
    return False
for sgn in (1, -1):
    # start at the highest slab where the outermost separate piece appears, then follow it down continuously
    def track(tol):
        best = []
        for i, per in enumerate(cands[sgn]):
            if not per: continue
            start = max(per, key=lambda q: q[0] * sgn)
            tr, miss, j = [start], 0, i + 1
            while j < len(cands[sgn]) and miss <= 4:
                # predict x from a line through the recent track so an angled (A-pose) forearm is followed
                px = tr[-1][0]
                if len(tr) >= 4 and cands[sgn][j]:
                    last = np.array([(t_[2], t_[0]) for t_ in tr[-8:]])
                    k1, k0 = np.polyfit(last[:, 0], last[:, 1], 1) if np.ptp(last[:, 0]) > 1e-6 else (0.0, last[-1, 1])
                    px = k1 * cands[sgn][j][0][2] + k0
                nx = [q for q in cands[sgn][j] if abs(q[0] - px) < tol and abs(q[1] - tr[-1][1]) < 0.05 * H and not on_leg(q, j)]
                if nx: tr.append(max(nx, key=lambda q: q[0] * sgn)); miss = 0   # the arm is the outermost section; drifts are always medial
                else: miss += 1
                j += 1
            if len(tr) > len(best): best = tr
            if len(best) > 20: break
        return best
    # strict first; a looser follow only wins if it reaches further AND ends out at the hand, not drifted onto the hip
    best = track(0.045 * H)
    loose = track(0.065 * H)
    if loose and (not best or loose[-1][2] < best[-1][2] - 0.02 * H) and abs(loose[-1][0]) >= abs(loose[0][0]) * 0.85:
        best = loose
    if best:
        seeds = np.concatenate([t_[4] for t_ in best])
        arr = np.array([t_[:4] for t_ in best])
        k = 2   # median-smooth the centreline and radius
        sm = np.array([np.median(arr[max(0, i - k):i + k + 1], axis=0) for i in range(len(arr))]); sm[:, 2] = arr[:, 2]
        best = [tuple(r_) for r_ in sm]
    arm_track[sgn] = best
    arm_seeds[sgn] = seeds if best else np.zeros(0, int)
# An arm pressed against the body loses its track early; generated characters are near-symmetric in the A-pose,
# so mirror the other side's arm when one side is much shorter.
def _ext(t): return (t[0][2] - t[-1][2]) if t else 0.0
for sgn in (1, -1):
    other = arm_track[-sgn]
    if other and _ext(arm_track[sgn]) < 0.7 * _ext(other):
        mt, ms = [], []
        for (x_, y_, z_, r_) in other:
            mt.append((-x_, y_, z_, r_))
            sl_ = np.where((vs[:, 2] >= z_ - 0.5 * CELL) & (vs[:, 2] < z_ + 0.5 * CELL))[0]
            ms.append(sl_[np.hypot(vs[sl_, 0] + x_, vs[sl_, 1] - y_) < r_ * 1.1])
        print('TRIPO arm', 'L' if sgn > 0 else 'R', 'mirrored from the other side (%.2f vs %.2f)' % (_ext(arm_track[sgn]) / H, _ext(other) / H))
        arm_track[sgn] = mt; arm_seeds[sgn] = np.concatenate(ms) if ms else np.zeros(0, int)
for sgn in (1, -1):
    best = arm_track[sgn]; seeds = arm_seeds[sgn]
    if '--armdbg' in A:
        for t_ in best: print('  trk z %.3f x %.3f y %.3f r %.3f' % ((t_[2] - mn.z) / H, t_[0] / H, t_[1] / H, t_[3] / H))
    print('TRIPO arm', 'L' if sgn > 0 else 'R', len(best), 'slabs', 'z %.2f..%.2f' % ((best[0][2] - mn.z) / H, (best[-1][2] - mn.z) / H) if best else '')
    if not best: continue
    tz = np.array([t_[2] for t_ in best])[::-1]; tx = np.array([t_[0] for t_ in best])[::-1]
    ty = np.array([t_[1] for t_ in best])[::-1]; tr_ = np.array([t_[3] for t_ in best])[::-1]
    m = (vs[:, 0] * sgn > 0.04 * H) & (vs[:, 2] < tz[-1] + 0.01 * H) & (vs[:, 2] > tz[0] - 0.12 * H)
    cz = np.clip(vs[m, 2], tz[0], tz[-1])
    dxy = np.hypot(vs[m, 0] - np.interp(cz, tz, tx), vs[m, 1] - np.interp(cz, tz, ty))
    rr = np.maximum(np.interp(cz, tz, tr_), 0.022 * H)
    lim = rr * 1.3 + 0.006 * H
    below = vs[m, 2] < tz[0]
    lim[below] *= np.clip(1 - (tz[0] - vs[m, 2][below]) / (0.08 * H), 0.4, 1)   # fingertips taper
    lim_g = rr * 1.3 + 0.006 * H
    inside_ = np.zeros(len(vs), bool); inside_[np.where(m)[0][dxy < lim]] = True
    # seed only from separated cross-sections of the upper arm (reliable); the rest is reached through the mesh itself
    arm_label[seeds[inside_[seeds] & ~leg_mask[seeds] & (vs[seeds, 2] > tz[-1] - 0.22 * H)]] = sgn
    # grow across mesh edges inside a generous tube so a face never straddles arm / body
    cand_ = np.zeros(len(vs), bool); cand_[np.where(m)[0][dxy < lim_g * 1.35 + 0.012 * H]] = True
    # below the tracked end (hand) follow the mesh freely nearby; legs and shorts are already excluded
    _end = np.array([tx[0], np.interp(tz[0], tz, ty) if len(tz) else 0, tz[0]])
    cand_ |= (vs[:, 2] < tz[0] + 0.02 * H) & (np.linalg.norm(vs - _end, axis=1) < 0.15 * H) & (vs[:, 0] * sgn > 0.05 * H)
    cand_ &= (vs[:, 2] < tz[-1] - 0.05 * H) & ~leg_mask
    _cz = np.clip(vs[:, 2], tz[0], tz[-1])
    cand_ &= vs[:, 0] * sgn > np.interp(_cz, tz, tx) * sgn - np.clip(np.interp(_cz, tz, tr_), 0.022 * H, 1.25 * float(np.median(tr_))) * 1.15   # never medial of the arm
    ev_ = np.array([e.vertices[:] for e in obj.data.edges])
    from mathutils.kdtree import KDTree
    for _round in range(6):
        for _ in range(250):
            a_, b_ = ev_[:, 0], ev_[:, 1]
            grow = np.zeros(len(vs), bool)
            grow[b_[(arm_label[a_] == sgn) & cand_[b_]]] = True; grow[a_[(arm_label[b_] == sgn) & cand_[a_]]] = True
            new_ = grow & (arm_label == 0)
            if not new_.any(): break
            arm_label[new_] = sgn
        # hop small gaps (a hand modelled as a separate shell at the wrist seam)
        li = np.where(arm_label == sgn)[0]; kd = KDTree(len(li))
        for k_, i_ in enumerate(li): kd.insert(vs[i_], k_)
        kd.balance()
        hop = [i_ for i_ in np.where(cand_ & (arm_label == 0))[0] if kd.find(vs[i_])[2] < 0.012 * H]
        if not hop: break
        arm_label[hop] = sgn
    if '--handdbg' in A and sgn == -1:
        hb = (vs[:, 0] < -0.15 * H) & (vs[:, 2] > Zf(0.36)) & (vs[:, 2] < Zf(0.44))
        print('HANDDBG n', int(hb.sum()), 'lab', int((arm_label[hb] == sgn).sum()), 'leg', int(leg_mask[hb].sum()), 'shorts', int(shorts_px[hb].sum()), 'cand', int(cand_[hb].sum()), 'tz0 %.3f tzT %.3f' % ((tz[0] - mn.z) / H, (tz[-1] - mn.z) / H), 'end', _end / H)
    # an unlabelled vertex mostly surrounded by arm is arm (stray fingertip / seam vertices)
    for _ in range(3):
        a_, b_ = ev_[:, 0], ev_[:, 1]
        deg = np.bincount(np.r_[a_, b_], minlength=len(vs))
        armn = np.bincount(np.r_[a_[arm_label[b_] == sgn], b_[arm_label[a_] == sgn]], minlength=len(vs))
        arm_label[(arm_label == 0) & (deg > 0) & (armn * 2 >= deg) & (vs[:, 0] * sgn > 0.045 * H) & ~leg_mask] = sgn
# islands touching the arm (a hand modelled as its own shell) that lie in the arm's reach join it
from mathutils.kdtree import KDTree
for sgn in (1, -1):
    idx_ = np.where(arm_label == sgn)[0]
    if not len(idx_): continue
    kd = KDTree(len(idx_))
    for k_, i_ in enumerate(idx_): kd.insert(vs[i_], k_)
    kd.balance()
    near = np.zeros(len(vs), bool)
    cand_v = np.where((arm_label == 0) & (vs[:, 0] * sgn > 0.05 * H) & ~leg_mask)[0]
    for i_ in cand_v:
        if kd.find(vs[i_])[2] < 0.015 * H: near[i_] = True
    _isl_tmp = None
    near_by_isl = {}
    globals()['_near_' + str(sgn)] = near
# mesh islands (separate shells: fingers, sleeve layers): an island that is mostly arm is all arm
_ev = np.array([e.vertices[:] for e in obj.data.edges])
_par = np.arange(len(vs))
def _find(i):
    while _par[i] != i: _par[i] = _par[_par[i]]; i = _par[i]
    return i
for a_, b_ in _ev:
    ra, rb = _find(a_), _find(b_)
    if ra != rb: _par[ra] = rb
isl = np.array([_find(i) for i in range(len(vs))])
for sgn in (1, -1):
    frac = np.bincount(isl, weights=(arm_label == sgn).astype(float), minlength=len(vs)) / np.maximum(np.bincount(isl, minlength=len(vs)), 1)
    near = globals().get('_near_' + str(sgn), np.zeros(len(vs), bool))
    touched = np.bincount(isl, weights=near.astype(float), minlength=len(vs)) > 0
    lat_ok = np.bincount(isl, weights=((vs[:, 0] * sgn > 0.05 * H) & ~leg_mask & (vs[:, 2] < Zf(0.6))).astype(float), minlength=len(vs)) / np.maximum(np.bincount(isl, minlength=len(vs)), 1)
    small = np.bincount(isl, minlength=len(vs)) < 1500
    sel = ((frac[isl] >= 0.5) | (touched[isl] & (lat_ok[isl] > 0.98) & small[isl])) & (arm_label == 0)
    print('TRIPO islands side', sgn, 'relabelled', int(sel.sum()))
    arm_label[sel] = sgn
# Hard bound: nothing medial to the arm's inner edge, and nothing above the tracked armpit, is arm.
for sgn in (1, -1):
    tr = arm_track[sgn]
    if not tr: arm_label[arm_label == sgn] = 0; continue
    tz = np.array([t_[2] for t_ in tr])[::-1]; tx = np.array([t_[0] for t_ in tr])[::-1]; trr = np.array([t_[3] for t_ in tr])[::-1]
    idx = np.where(arm_label == sgn)[0]
    cz = np.clip(vs[idx, 2], tz[0], tz[-1])
    # arm thickness: a section merged with the chest inflates r, so cap it near the arm's typical radius
    r_cap = np.clip(np.interp(cz, tz, trr), 0.022 * H, 1.25 * float(np.median(trr)))
    inner = np.interp(cz, tz, tx) * sgn - r_cap * 1.15 - 0.004 * H
    bad = (vs[idx, 0] * sgn < inner) | (vs[idx, 2] > tz[-1] - 0.05 * H)   # the contact band under the armpit is blended, not cut
    arm_label[idx[bad]] = 0
    print('TRIPO arm bound side', sgn, 'unlabelled', int(bad.sum()))
# Kit guard: below the elbow an arm is skin (or glove), never shirt red / shorts blue / sock green.
def _hd(h0): d_ = np.abs(_hue - h0); return np.minimum(d_, 1 - d_)
# the shirt's own hue, measured on the chest front (generated reds range from crimson to orange-red)
_chest = (np.abs(vs[:, 0]) < 0.05 * H) & (vs[:, 2] > Zf(0.62)) & (vs[:, 2] < Zf(0.70)) & (vs[:, 1] < np.median(vs[:, 1])) & (_sat > 0.4)
_shirt_h = float(np.median(np.where(_hue[_chest] > 0.5, _hue[_chest] - 1, _hue[_chest]))) % 1.0 if _chest.sum() > 10 else 0.0
_kit = (_mx > 0.12) & (((_sat > 0.45) & (_hd(_shirt_h) < 0.04)) | ((_sat > 0.3) & ((_hd(0.62) < 0.08) | (_hd(0.37) < 0.08))))
print('TRIPO shirt hue %.3f' % _shirt_h)
for sgn in (1, -1):
    tr = arm_track[sgn]
    if not tr: continue
    elz = tr[0][2] + (tr[-1][2] - tr[0][2]) * 0.45
    bad_ = (arm_label == sgn) & _kit & (vs[:, 2] < elz)
    arm_label[bad_] = 0
    print('TRIPO kit guard side', sgn, 'unlabelled', int(bad_.sum()))
# Athletic-fit sleeves: generated jerseys often have wide baggy sleeves that swing out like wings with the arm.
# Pull sleeve (kit-coloured arm) vertices in toward the arm's axis so the sleeve hugs the upper arm.
_moved = 0
_co = [v.co.copy() for v in obj.data.vertices]
for sgn in (1, -1):
    tr = arm_track[sgn]
    if len(tr) < 4: continue
    tz_a = np.array([t_[2] for t_ in tr])[::-1]; tx_a = np.array([t_[0] for t_ in tr])[::-1]; ty_a = np.array([t_[1] for t_ in tr])[::-1]
    rr_a = np.array([t_[3] for t_ in tr])[::-1]
    r_arm = float(np.percentile(rr_a, 30))            # bare-arm radius
    cap = max(r_arm * 1.35, 0.026 * H)
    for i in np.where((arm_label == sgn) & _kit)[0]:
        z_ = min(max(vs[i, 2], tz_a[0]), tz_a[-1])
        cx, cy = np.interp(z_, tz_a, tx_a), np.interp(z_, tz_a, ty_a)
        dx, dy = vs[i, 0] - cx, vs[i, 1] - cy
        d = math.hypot(dx, dy)
        if d > cap:
            f = cap / d
            obj.data.vertices[i].co.x = cx + dx * f; obj.data.vertices[i].co.y = cy + dy * f; _moved += 1
vs = np.array([v.co[:] for v in obj.data.vertices])
print('TRIPO sleeves tightened', _moved, 'verts')
# Rip the surface where arm meets body below the armpit (hands/arms touching the torso or shorts in the source):
# each face goes wholly to one side, so nothing is ever stretched between a swinging arm and the body.
_ap = {sgn: (arm_track[sgn][0][2] if arm_track[sgn] else Zf(0.74)) for sgn in (1, -1)}
# cut only from the elbow down (hands/forearms resting on the body); higher up a smooth stretch beats a hole
_elz = {sgn: (arm_track[sgn][0][2] + (arm_track[sgn][-1][2] - arm_track[sgn][0][2]) * 0.45 if arm_track[sgn] else Zf(0.6)) for sgn in (1, -1)}
bm = bmesh.new(); bm.from_mesh(obj.data); bm.verts.ensure_lookup_table(); bm.faces.ensure_lookup_table()
flab = {}
for f in bm.faces:
    ls = [int(arm_label[v.index]) for v in f.verts]
    nz_ = [l for l in ls if l]
    flab[f.index] = (max(set(nz_), key=nz_.count) if len(nz_) * 2 >= len(ls) else 0)
cut = [e for e in bm.edges if len(e.link_faces) == 2 and flab[e.link_faces[0].index] != flab[e.link_faces[1].index]
       and max(v.co.z for v in e.verts) < _elz[flab[e.link_faces[0].index] or flab[e.link_faces[1].index]]]
bmesh.ops.split_edges(bm, edges=cut)
bm.verts.ensure_lookup_table(); bm.faces.ensure_lookup_table()
nl = np.zeros(len(bm.verts), dtype=np.int8)
for f in bm.faces:
    if flab[f.index]:
        for v in f.verts: nl[v.index] = flab[f.index]
bm.to_mesh(obj.data); bm.free()
arm_label = nl
leg_mask = np.concatenate([leg_mask, np.zeros(len(nl) - len(leg_mask), bool)])
vs = np.array([v.co[:] for v in obj.data.vertices])
print('TRIPO rip', len(cut), 'edges; verts now', len(vs))
for sgn, side in ((1, 'L'), (-1, 'R')):
    tr = arm_track[sgn]
    if len(tr) >= 4:
        top, bot = tr[0], tr[-1]
        sh = Vector((top[0] - sgn * 0.01 * H, top[1], max(top[2] + 0.04 * H, Zf(0.765))))
        # fingertips: the lowest arm vertex of this side
        low = vs[arm_label == sgn]; lp = low[np.argmin(low[:, 2])]
        tip = Vector((bot[0], bot[1], float(lp[2])))
    else:
        sh = J(sgn * torso_hw * 0.95, Zf(0.785)); tip = J(sgn * 0.3 * H, Zf(0.45))
    d = tip - sh
    def on_track(f):
        z_ = sh.z + d.z * f
        if len(tr) >= 4:
            t_ = min(tr, key=lambda q: abs(q[2] - z_)); return Vector((t_[0], t_[1], z_))
        return sh + d * f
    elbow, wrist = on_track(0.47), on_track(0.80)
    bone('upperarm.' + side, sh, elbow, 'chest')
    bone('forearm.' + side, elbow, wrist, 'upperarm.' + side)
    bone('hand.' + side, wrist, tip, 'forearm.' + side)
    # legs: centre of each leg's cross-section at hip/knee/ankle height
    def leg_x(f):
        sl = slab(Zf(f - 0.02), Zf(f + 0.02)); sl = sl[(sl[:, 0] * sgn) > 0.01]
        return float(np.median(sl[:, 0])) if len(sl) else sgn * 0.06 * H
    hip = J(leg_x(0.44), Zf(0.49)); knee = J(leg_x(0.27), Zf(0.27)); ankle = J(leg_x(0.07), Zf(0.055))
    bone('thigh.' + side, hip, knee, 'hips')
    bone('shin.' + side, knee, ankle, 'thigh.' + side)
    bone('foot.' + side, ankle, Vector((ankle.x, mn.y + 0.03, Zf(0.015))), 'shin.' + side)
bpy.ops.object.mode_set(mode='OBJECT')
# Generated meshes are many overlapping shells, so heat weighting fails on them. Skin a watertight voxel proxy
# of the body instead, then transfer its weights to the real mesh (nearest surface, interpolated).
# Heat weighting can fail on a proxy (thin gaps, stray shells): retry coarser, then fall back to envelopes.
for vox in (0.009, 0.013, 0.018, None):
    proxy = obj.copy(); proxy.data = obj.data.copy(); scene.collection.objects.link(proxy)
    rm = proxy.modifiers.new('vox', 'REMESH'); rm.mode = 'VOXEL'; rm.voxel_size = (vox or 0.018) * H; rm.use_smooth_shade = True
    bpy.ops.object.select_all(action='DESELECT'); proxy.select_set(True); bpy.context.view_layer.objects.active = proxy
    bpy.ops.object.modifier_apply(modifier='vox')
    proxy.data.materials.clear()
    bpy.ops.object.select_all(action='DESELECT'); proxy.select_set(True); ro.select_set(True); bpy.context.view_layer.objects.active = ro
    if vox is None:
        for b_ in arm.bones: pass
        bpy.ops.object.parent_set(type='ARMATURE_ENVELOPE')
    else:
        bpy.ops.object.parent_set(type='ARMATURE_AUTO')
    wn = sum(1 for v in proxy.data.vertices if v.groups)
    if wn > 0.9 * len(proxy.data.vertices) or vox is None: break
    print('TRIPO proxy heat failed at voxel', vox, '- retrying')
    bpy.data.objects.remove(proxy)
print('TRIPO proxy', len(proxy.data.vertices), 'verts; weighted', sum(1 for v in proxy.data.vertices if v.groups))
for b in arm.bones: obj.vertex_groups.new(name=b.name)
dt = obj.modifiers.new('dt', 'DATA_TRANSFER'); dt.object = proxy
dt.use_vert_data = True; dt.data_types_verts = {'VGROUP_WEIGHTS'}; dt.vert_mapping = 'POLYINTERP_NEAREST'
dt.layers_vgroup_select_src = 'ALL'; dt.layers_vgroup_select_dst = 'NAME'
bpy.ops.object.select_all(action='DESELECT'); obj.select_set(True); bpy.context.view_layer.objects.active = obj
bpy.ops.object.modifier_apply(modifier='dt')
print('WSTAGE after-transfer', sum(1 for v in obj.data.vertices if sum(g.weight for g in v.groups) < 0.01), 'of', len(obj.data.vertices))
bpy.data.objects.remove(proxy)
obj.parent = ro
am = obj.modifiers.new('Armature', 'ARMATURE'); am.object = ro
bpy.ops.object.select_all(action='DESELECT'); obj.select_set(True); bpy.context.view_layer.objects.active = obj
bpy.ops.object.mode_set(mode='WEIGHT_PAINT')
bpy.ops.object.vertex_group_smooth(group_select_mode='ALL', factor=0.5, repeat=4, expand=0.0)
bpy.ops.object.vertex_group_normalize_all(group_select_mode='ALL', lock_active=False)
bpy.ops.object.mode_set(mode='OBJECT')
print('WSTAGE after-smooth', sum(1 for v in obj.data.vertices if sum(g.weight for g in v.groups) < 0.01), 'of', len(obj.data.vertices))
# Pelvis: blend thighs toward hips so leg swings don't drag the shorts outward.
hg = obj.vertex_groups.get('hips')
for v in obj.data.vertices:
    z = v.co.z
    if Zf(0.42) < z < Zf(0.56):
        for g in v.groups:
            if obj.vertex_groups[g.group].name.startswith('thigh.') and abs(v.co.x) < 0.09 * H:
                moved = g.weight * min(0.8, (z - Zf(0.42)) / (0.14 * H)); g.weight -= moved
                hg.add([v.index], moved, 'ADD')
# Arm bones only move vertices near the arm chain (hands resting near the shorts never drag them).
def seg_d(p, a, b):
    ab = b - a; t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (p - (a + ab * t)).length
chains = {s_: [(arm.bones[n + s_].head_local.copy(), arm.bones[n + s_].tail_local.copy()) for n in ('upperarm.', 'forearm.', 'hand.')] for s_ in 'LR'}
arm_idx = {g.index: g.name for g in obj.vertex_groups if g.name.startswith(('forearm', 'hand', 'upperarm'))}
R = 0.045 * H
# Detected arm vertices: weights come purely from the arm chain (smooth blend at elbow/wrist, chest near the armpit).
armpit = {sgn: (arm_track[sgn][0][2] if arm_track[sgn] else Zf(0.74)) for sgn in (1, -1)}
cg = obj.vertex_groups['chest']
for v in obj.data.vertices:
    sgn = int(arm_label[v.index])
    if not sgn: continue
    side = 'L' if sgn > 0 else 'R'
    for gi in [g.group for g in v.groups]: obj.vertex_groups[gi].remove([v.index])   # ids first: removing invalidates element refs
    ds = [seg_d(v.co, a, b) for a, b in chains[side]]
    ws = [math.exp(-(dd / (0.035 * H)) ** 2) + 1e-6 for dd in ds]
    k = 1.0
    tot = sum(ws)
    for n_, w_ in zip(('upperarm.', 'forearm.', 'hand.'), ws):
        obj.vertex_groups[n_ + side].add([v.index], k * w_ / tot, 'REPLACE')
    if k < 1: cg.add([v.index], 1 - k, 'REPLACE')
for v in obj.data.vertices:
    if arm_label[v.index]: continue
    for g in list(v.groups):
        if g.group in arm_idx and g.weight > 0:
            d = min(seg_d(v.co, a, b) for a, b in chains[arm_idx[g.group][-1]])
            # Inside the torso silhouette below the armpit it is shirt, never arm.
            inside = v.co.z < armpit[1 if v.co.x > 0 else -1] - 0.01 * H   # below the armpit and not arm: body
            if inside: d = max(d, 2 * R)
            if d > R:
                f = min(1.0, (d - R) / (0.5 * R)); moved = g.weight * f; g.weight -= moved
                (hg if v.co.z < Zf(0.6) else obj.vertex_groups['chest']).add([v.index], moved, 'ADD')
# Shoulder + sleeve (above the detected arm): chest→upperarm blend by position along the upper arm, so the sleeve
# travels with the arm and the shoulder stretches smoothly instead of tearing.
arm_names = {g.index for g in obj.vertex_groups if g.name.startswith(('upperarm', 'forearm', 'hand'))}
tz_, tx_, tr_s = {}, {}, {}
for sgn in (1, -1):
    tr = arm_track[sgn] or [(sgn * torso_hw, 0.0, Zf(0.7), 0.03 * H)]
    tz_[sgn] = np.array([t_[2] for t_ in tr])[::-1]; tx_[sgn] = np.array([t_[0] for t_ in tr])[::-1]; tr_s[sgn] = np.array([t_[3] for t_ in tr])[::-1]
for sgn, side in ((1, 'L'), (-1, 'R')):
    ub = arm.bones['upperarm.' + side]; sh_, el_ = ub.head_local, ub.tail_local
    dir_ = (el_ - sh_).normalized(); ug = obj.vertex_groups['upperarm.' + side]; nsh = 0
    print('TRIPO shoulder', side, 'sh z %.3f x %.3f  el z %.3f x %.3f armpit %.3f torso_hw %.3f' % ((sh_.z - mn.z) / H, sh_.x / H, (el_.z - mn.z) / H, el_.x / H, (armpit[sgn] - mn.z) / H, torso_hw / H))
    for v in obj.data.vertices:
        if arm_label[v.index] or v.co.x * sgn < 0.02 * H: continue
        if not (armpit[sgn] < v.co.z < sh_.z + 0.09 * H): continue   # below the armpit, anything that isn't arm is body
        # below the armpit: lateral position against the arm's inner edge (arm and flank touch there)
        z_ = min(max(v.co.z, tz_[sgn][0]), tz_[sgn][-1])
        edge = np.interp(z_, tz_[sgn], tx_[sgn]) * sgn - max(np.interp(z_, tz_[sgn], tr_s[sgn]), 0.022 * H) - 0.012 * H
        lf = min(1.0, max(0.0, (v.co.x * sgn - edge) / (0.03 * H)))
        # above it: along the upper arm from the shoulder, and outward of the shoulder
        t = (v.co - sh_).dot(dir_)
        vf = min(1.0, max(0.0, (t + 0.035 * H) / (0.07 * H))) * min(1.0, max(0.0, (v.co.x * sgn - (sh_.x * sgn - 0.045 * H)) / (0.04 * H)))
        a_ = min(1.0, max(0.0, (v.co.z - armpit[sgn]) / (0.03 * H)))
        w = vf * a_   # no lateral blend below/at the armpit: on broad chests the flank overlaps the arm in x (the 'jersey wing')
        w *= min(1.0, max(0.0, (0.085 * H - seg_d(v.co, sh_, el_)) / (0.03 * H)))
        w = w * w * (3 - 2 * w)
        if w <= 0.01: continue
        rest_ = [(g.group, g.weight) for g in v.groups if g.group not in arm_names]
        for gi in [g.group for g in v.groups if g.group in arm_names]: obj.vertex_groups[gi].remove([v.index])
        tot = sum(x for _, x in rest_) or 1
        for gi, x in rest_: obj.vertex_groups[gi].add([v.index], (1 - w) * x / tot, 'REPLACE')
        if not rest_: cg.add([v.index], 1 - w, 'REPLACE')
        ug.add([v.index], w, 'REPLACE'); nsh += 1
    print('TRIPO shoulder verts', side, nsh)
# Flank under the arm: a broad, smooth share of upper-arm weight that fades out toward the waist. With the sleeve
# fused to the flank in generated meshes, a hard arm/body boundary fans into a 'wing' when the arm lifts; spreading
# the transition makes the shirt ride up with the arm like real fabric instead.
nfl = 0
for sgn, side in ((1, 'L'), (-1, 'R')):
    ug = obj.vertex_groups['upperarm.' + side]
    ap = armpit[sgn]
    for v in obj.data.vertices:
        if arm_label[v.index] or v.co.x * sgn < 0.03 * H: continue
        dz = ap - v.co.z
        if dz < -0.01 * H or dz > 0.22 * H: continue
        edge = torso_edge(v.co.z)
        lat = min(1.0, max(0.0, (v.co.x * sgn - (edge - 0.06 * H)) / (0.05 * H)))   # outer flank only
        w = 0.7 * lat * math.exp(-max(dz, 0) / (0.09 * H))
        if w < 0.02: continue
        cur = {g.group: g.weight for g in v.groups}
        tot = sum(x for gi, x in cur.items() if gi not in arm_names) or 1
        for gi in list(cur):
            if gi in arm_names: obj.vertex_groups[gi].remove([v.index])
        for gi, x in cur.items():
            if gi not in arm_names: obj.vertex_groups[gi].add([v.index], (1 - w) * x / tot, 'REPLACE')
        ug.add([v.index], w, 'REPLACE'); nfl += 1
print('TRIPO flank gradient verts', nfl)
bpy.ops.object.vertex_group_normalize_all(group_select_mode='ALL', lock_active=False)
heads = [(b.name, (b.head_local + b.tail_local) / 2) for b in arm.bones]
body_heads = [h for h in heads if not h[0].startswith(('upperarm', 'forearm', 'hand'))]
nfb = 0
for v in obj.data.vertices:
    if sum(g.weight for g in v.groups) < 0.01:
        pool = heads if arm_label[v.index] else body_heads   # a stray body vertex must never snap to a hand
        obj.vertex_groups[min(pool, key=lambda h: (h[1] - v.co).length)[0]].add([v.index], 1.0, 'REPLACE'); nfb += 1
print('TRIPO zero-weight fallbacks', nfb)

# ------------------------------------------------------------------ stretch repair (safety net)
# Pose the rig in a few test poses. Any hand/forearm-to-body edge that stretches absurdly is either a hand left
# behind (skin, out to the side: pull the whole skin patch onto the arm) or fused geometry (cut it).
def _Rw(axis, deg): return Matrix.Rotation(math.radians(deg), 4, axis)
_TEST = [{'upperarm.L': _Rw('X', -75), 'forearm.L': _Rw('X', -85), 'upperarm.R': _Rw('X', 60), 'forearm.R': _Rw('X', -70)},
         {'upperarm.R': _Rw('X', -75), 'forearm.R': _Rw('X', -85), 'upperarm.L': _Rw('X', 60), 'forearm.L': _Rw('X', -70)},
         {'upperarm.L': _Rw('Y', -140), 'upperarm.R': _Rw('Y', 140)},
         {'upperarm.L': _Rw('Y', -80) @ _Rw('X', -30), 'upperarm.R': _Rw('Y', 80) @ _Rw('X', 40)}]
_rest_m = {b.name: b.matrix_local.copy() for b in arm.bones}
def _posed(pose):
    tot = {}
    for b in arm.bones:
        hd = b.head_local
        tot[b.name] = (tot[b.parent.name] if b.parent else Matrix()) @ Matrix.Translation(hd) @ pose.get(b.name, Matrix()) @ Matrix.Translation(-hd)
        ro.pose.bones[b.name].matrix = tot[b.name] @ _rest_m[b.name]
        bpy.context.view_layer.update()
    co = np.array([v.co[:] for v in obj.evaluated_get(bpy.context.evaluated_depsgraph_get()).data.vertices])
    for pb in ro.pose.bones: pb.matrix_basis = Matrix()
    bpy.context.view_layer.update()
    return co
_low_arm = {g.index for g in obj.vertex_groups if g.name.startswith(('forearm', 'hand'))}
_all_arm = {g.index for g in obj.vertex_groups if g.name.startswith(('upperarm', 'forearm', 'hand'))}
for _it in range(3):
    E_ = np.array([e.vertices[:] for e in obj.data.edges]); rc = np.array([v.co[:] for v in obj.data.vertices])
    L0_ = np.linalg.norm(rc[E_[:, 0]] - rc[E_[:, 1]], axis=1) + 1e-6
    ratio = np.zeros(len(E_))
    for pz in _TEST:
        pc = _posed(pz); ratio = np.maximum(ratio, np.linalg.norm(pc[E_[:, 0]] - pc[E_[:, 1]], axis=1) / L0_)
    lowarm = np.array([sum(g.weight for g in v.groups if g.group in _low_arm) for v in obj.data.vertices])
    armw = np.array([sum(g.weight for g in v.groups if g.group in _all_arm) for v in obj.data.vertices])
    bad = np.where((ratio > 3.5) & (((lowarm[E_[:, 0]] > 0.5) & (armw[E_[:, 1]] < 0.5)) | ((lowarm[E_[:, 1]] > 0.5) & (armw[E_[:, 0]] < 0.5))))[0]
    # The 'jersey wing': where the source mesh fuses the sleeve's underside to the shirt flank, those faces fan
    # open when the arm moves. Cut sleeve-to-flank edges below the armpit that stretch badly (the character is
    # rendered double-sided, so a slit shows shirt, not background).
    _apz = min(armpit.values()) - 0.03 * H   # only the seam well below the true armpit; the armpit itself stretches like fabric
    lowz = (rc[E_[:, 0], 2] < _apz) & (rc[E_[:, 1], 2] < _apz)
    wing = np.where((ratio > 2.5) & lowz & (np.abs(armw[E_[:, 0]] - armw[E_[:, 1]]) > 0.45))[0]
    wing = np.setdiff1d(wing, bad)
    if not len(bad) and not len(wing): break
    nv = len(rc); kit_ = _kit if len(_kit) == nv else np.concatenate([_kit, np.zeros(nv - len(_kit), bool)])
    adj = [[] for _ in range(nv)]
    for a_, b_ in E_: adj[a_].append(b_); adj[b_].append(a_)
    pulled, cut = 0, []
    for ei in bad:
        a_, b_ = E_[ei]
        if lowarm[a_] < lowarm[b_]: a_, b_ = b_, a_          # a_ = arm side, b_ = body side
        sgn = 1 if rc[a_, 0] > 0 else -1
        elz_ = (arm_track[sgn][0][2] + (arm_track[sgn][-1][2] - arm_track[sgn][0][2]) * 0.45) if arm_track[sgn] else Zf(0.6)
        if not kit_[b_] and rc[b_, 0] * sgn > torso_edge(rc[b_, 2]) and armw[b_] < 0.5 and rc[b_, 2] < elz_:
            # flood the unlabelled skin patch around b_ (a hand left behind) and give it a_'s weights
            src = [(g.group, g.weight) for g in obj.data.vertices[a_].groups]
            stack, seen = [b_], {b_}
            while stack and len(seen) < 900:
                u = stack.pop()
                for w_ in adj[u]:
                    if w_ not in seen and armw[w_] < 0.5 and not kit_[w_] and rc[w_, 0] * sgn > torso_edge(rc[w_, 2]) and abs(rc[w_, 2] - rc[b_, 2]) < 0.12 * H and rc[w_, 2] < elz_:
                        seen.add(w_); stack.append(w_)
            if len(seen) < 900:
                for u in seen:
                    for gi in [g.group for g in obj.data.vertices[int(u)].groups]: obj.vertex_groups[gi].remove([int(u)])
                    for gi, w in src: obj.vertex_groups[gi].add([int(u)], w, 'REPLACE')
                    armw[u] = 1.0
                pulled += len(seen); continue
        cut.append(int(ei))
    # wing edges live inside mixed triangles (one corner on the arm, two on the flank): splitting edges can't
    # un-stretch those, so remove the bridge faces themselves.
    wing_faces = []
    if len(wing):
        wset = set(map(int, wing)); ekey = {tuple(sorted(e)): i for i, e in enumerate(E_.tolist())}
        for f in obj.data.polygons:
            vv = list(f.vertices)
            if any(ekey.get(tuple(sorted((vv[k], vv[(k + 1) % len(vv)])))) in wset for k in range(len(vv))):
                wing_faces.append(f.index)
    if False and wing_faces:
        bm = bmesh.new(); bm.from_mesh(obj.data); bm.faces.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[bm.faces[i] for i in wing_faces], context='FACES_ONLY')
        bm.to_mesh(obj.data); bm.free()
        E_ = np.array([e.vertices[:] for e in obj.data.edges])
        bad = bad[bad < len(E_)]
    if cut:
        bm = bmesh.new(); bm.from_mesh(obj.data); bm.edges.ensure_lookup_table()
        bmesh.ops.split_edges(bm, edges=[bm.edges[i] for i in cut]); bm.to_mesh(obj.data); bm.free()
        pad = len(obj.data.vertices) - len(arm_label)
        if pad > 0:
            arm_label = np.concatenate([arm_label, np.zeros(pad, np.int8)]); leg_mask = np.concatenate([leg_mask, np.zeros(pad, bool)])
    print('TRIPO stretch repair pass', _it, 'bad edges', len(bad), 'wing faces removed', len(wing_faces), 'pulled', pulled, 'cut', len(cut))

if '--labeldbg' in A:
    _ai = {g.index: g.name for g in obj.vertex_groups if g.name.startswith(('upperarm', 'forearm', 'hand'))}
    _cnt = 0
    for v in obj.data.vertices:
        if arm_label[v.index] or v.co.z > Zf(0.5): continue
        aw = [(g.weight, _ai[g.group]) for g in v.groups if g.group in _ai and g.weight > 0.3]
        if aw and _cnt < 6:
            _cnt += 1; print('LEAK z %.3f x %.3f' % ((v.co.z - mn.z) / H, v.co.x / H), [(round(w, 2), n) for w, n in aw], 'all', [(obj.vertex_groups[g.group].name, round(g.weight, 2)) for g in v.groups])
    lc = obj.data.color_attributes.new(name='lab', type='FLOAT_COLOR', domain='POINT')
    ai = {g.index for g in obj.vertex_groups if g.name.startswith(('upperarm', 'forearm', 'hand'))}
    for v in obj.data.vertices:
        aw = sum(g.weight for g in v.groups if g.group in ai)
        l_ = arm_label[v.index]
        lc.data[v.index].color = (aw, 0.2 if l_ == 0 else 0.9, 0.9 if leg_mask[v.index] else (0.2 if l_ >= 0 else 0.6), 1)
    obj.data.materials.clear()
    lm = bpy.data.materials.new('lab'); lm.use_nodes = True; t = lm.node_tree; t.nodes.clear()
    o2 = t.nodes.new('ShaderNodeOutputMaterial'); e = t.nodes.new('ShaderNodeEmission'); vc = t.nodes.new('ShaderNodeVertexColor'); vc.layer_name = 'lab'
    t.links.new(vc.outputs[0], e.inputs[0]); t.links.new(e.outputs[0], o2.inputs[0]); obj.data.materials.append(lm)
    ro.hide_render = True
    scene.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in [x.identifier for x in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items] else 'BLENDER_EEVEE'
    scene.render.resolution_x, scene.render.resolution_y = 700, 700
    cd = bpy.data.cameras.new('c'); cd.type = 'ORTHO'; cd.ortho_scale = H * 0.55
    cam = bpy.data.objects.new('c', cd); scene.collection.objects.link(cam); scene.camera = cam
    for nm, deg in (('front', 0), ('side', 90), ('back', 180)):
        a = math.radians(deg)
        cam.location = (math.sin(a) * 6, -math.cos(a) * 6, mn.z + H * float(arg('--labz', '0.62'))); cam.rotation_euler = (math.radians(90), 0, a)
        scene.render.filepath = os.path.join(arg('--labeldbg'), f'{NAME}_lab_{nm}.png'); bpy.ops.render.render(write_still=True)
    sys.exit(0)

# ------------------------------------------------------------------ stress test (--stress): extreme poses → renders + stretch stats
if '--stress' in A:
    def Rw(axis, deg): return Matrix.Rotation(math.radians(deg), 4, axis)
    POSES = {'rest': {},
        'sprint': {'upperarm.L': Rw('X', -75), 'forearm.L': Rw('X', -85), 'upperarm.R': Rw('X', 60), 'forearm.R': Rw('X', -70),
                   'thigh.L': Rw('X', -65), 'shin.L': Rw('X', 40), 'thigh.R': Rw('X', 35), 'shin.R': Rw('X', 95), 'spine': Rw('X', -12)},
        'sprint2': {'upperarm.R': Rw('X', -75), 'forearm.R': Rw('X', -85), 'upperarm.L': Rw('X', 60), 'forearm.L': Rw('X', -70),
                    'thigh.R': Rw('X', -65), 'shin.R': Rw('X', 40), 'thigh.L': Rw('X', 35), 'shin.L': Rw('X', 95)},
        'armsup': {'upperarm.L': Rw('Y', -140), 'upperarm.R': Rw('Y', 140), 'forearm.L': Rw('Y', -20), 'forearm.R': Rw('Y', 20)},
        'kick': {'thigh.R': Rw('X', -95), 'shin.R': Rw('X', 20), 'upperarm.L': Rw('Y', -70), 'upperarm.R': Rw('X', 50), 'chest': Rw('Z', 20)},
        'tackle': {'thigh.L': Rw('X', -40), 'shin.L': Rw('X', 90), 'thigh.R': Rw('Y', 45), 'upperarm.L': Rw('Y', -60), 'upperarm.R': Rw('Y', 60), 'forearm.R': Rw('X', -60)},
    }
    def _align_down(side):
        b = arm.bones['upperarm.' + side]; d = (b.tail_local - b.head_local).normalized()
        return d.rotation_difference(Vector((0, 0, -1))).to_matrix().to_4x4()
    # the game's pose path: arm first straightened to hang down, then raised overhead (knee-slide / sky)
    POSES['gameup'] = {'upperarm.L': Rw('Y', -132) @ _align_down('L'), 'upperarm.R': Rw('Y', 132) @ _align_down('R'),
                       'spine': Rw('X', 14), 'chest': Rw('X', 14)}
    order = [b.name for b in arm.bones]  # parents precede children
    rest = {b.name: b.matrix_local.copy() for b in arm.bones}
    ev = lambda: np.array([v.co[:] for v in obj.evaluated_get(bpy.context.evaluated_depsgraph_get()).data.vertices])
    rest_co = np.array([v.co[:] for v in obj.data.vertices])
    E = np.array([e.vertices[:] for e in obj.data.edges])
    L0 = np.linalg.norm(rest_co[E[:, 0]] - rest_co[E[:, 1]], axis=1) + 1e-6
    gname_ = {g.index: g.name for g in obj.vertex_groups}
    dom = [gname_[max(v.groups, key=lambda g: g.weight).group] if v.groups else '-' for v in obj.data.vertices]
    obj.data.materials.clear()
    pm = bpy.data.materials.new('prev'); pm.use_nodes = True
    t = pm.node_tree; t.nodes.clear()
    o2 = t.nodes.new('ShaderNodeOutputMaterial'); e = t.nodes.new('ShaderNodeEmission'); ti = t.nodes.new('ShaderNodeTexImage')
    ti.image = tex; t.links.new(ti.outputs[0], e.inputs[0]); t.links.new(e.outputs[0], o2.inputs[0])
    if '--catdbg' in A:
        vc_ = t.nodes.new('ShaderNodeVertexColor'); vc_.layer_name = 'cat'; t.links.new(vc_.outputs[0], e.inputs[0])
    pm.use_backface_culling = False   # the game renders characters double-sided
    obj.data.materials.append(pm)
    ro.hide_render = True
    scene.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in [x.identifier for x in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items] else 'BLENDER_EEVEE'
    scene.render.resolution_x, scene.render.resolution_y = 500, 600
    w = bpy.data.worlds.new('w'); scene.world = w; w.color = (0.25, 0.25, 0.28)
    cd = bpy.data.cameras.new('c'); cd.type = 'ORTHO'; cd.ortho_scale = H * 1.25
    cam = bpy.data.objects.new('c', cd); scene.collection.objects.link(cam); scene.camera = cam
    outs = []
    _chainL = {g.index for g in obj.vertex_groups if g.name in ('upperarm.L', 'forearm.L', 'hand.L')}
    _foreign = []
    for v in obj.data.vertices:
        if arm_label[v.index] == 1:
            fw = sum(g.weight for g in v.groups if g.group not in _chainL)
            if fw > 0.05: _foreign.append((round(fw, 2), [(obj.vertex_groups[g.group].name, round(g.weight, 2)) for g in v.groups]))
    print('STRESS foreign-weighted L arm verts', len(_foreign), _foreign[:3])
    _hv = [v for v in obj.data.vertices if arm_label[v.index] == 1]
    print('STRESS sample L arm weights', [[(obj.vertex_groups[g.group].name, round(g.weight, 2)) for g in v.groups] for v in _hv[::max(1, len(_hv) // 6)]][:6])
    if '--catdbg' in A:
        # colour by weight category: red = labelled arm, yellow = blended arm weight, grey = body
        lc = obj.data.color_attributes.new(name='cat', type='FLOAT_COLOR', domain='POINT')
        ai = {g.index for g in obj.vertex_groups if g.name.startswith(('upperarm', 'forearm', 'hand'))}
        for v in obj.data.vertices:
            aw = sum(g.weight for g in v.groups if g.group in ai)
            c_ = (0.9, 0.1, 0.1) if arm_label[v.index] else ((0.9, 0.8, 0.1) if aw > 0.02 else (0.5, 0.5, 0.5))
            lc.data[v.index].color = (*c_, 1)
        tex_node_src = 'cat'
    _an = {g.index for g in obj.vertex_groups if g.name.startswith(('upperarm', 'forearm', 'hand'))}
    for zz0, zz1 in ((0.60, 0.70), (0.70, 0.78), (0.78, 0.84)):
        sel_ = [v for v in obj.data.vertices if abs(v.co.x) < 0.07 * H and Zf(zz0) < v.co.z < Zf(zz1)]
        aw = [sum(g.weight for g in v.groups if g.group in _an) for v in sel_]
        print('STRESS centre z %.2f-%.2f n %d armw>0.05: %d max %.2f  labelled %d' % (zz0, zz1, len(sel_), sum(1 for a in aw if a > 0.05), max(aw) if aw else 0, sum(1 for v in sel_ if arm_label[v.index])))
    for pname, pose in POSES.items():
        tot = {}
        for bn in order:
            b = arm.bones[bn]; hd = b.head_local
            loc = Matrix.Translation(hd) @ pose.get(bn, Matrix()) @ Matrix.Translation(-hd)
            tot[bn] = (tot[b.parent.name] if b.parent else Matrix()) @ loc
            ro.pose.bones[bn].matrix = tot[bn] @ rest[bn]
            bpy.context.view_layer.update()
        co = ev()
        r = np.linalg.norm(co[E[:, 0]] - co[E[:, 1]], axis=1) / L0
        bad = np.argsort(-r)[:8]
        pairs = {}
        for i in np.where(r > 2.0)[0]:
            k = tuple(sorted((dom[E[i, 0]], dom[E[i, 1]]))); pairs[k] = pairs.get(k, 0) + 1
        for i in bad[:5]:
            a_, b_ = E[i]
            print('   worst r %.0f  A z %.3f x %.3f lab %d %s | B z %.3f x %.3f lab %d %s' % (r[i], (rest_co[a_, 2] - mn.z) / H, rest_co[a_, 0] / H, arm_label[a_], dom[a_], (rest_co[b_, 2] - mn.z) / H, rest_co[b_, 0] / H, arm_label[b_], dom[b_]))
        print('STRESS', pname, 'edges>2x', int((r > 2).sum()), '>4x', int((r > 4).sum()), 'max %.1f' % r.max(), sorted(pairs.items(), key=lambda x: -x[1])[:6])
        for nm, deg in (('34', 35), ('side', 90)):
            a = math.radians(deg)
            cam.location = (math.sin(a) * 6, -math.cos(a) * 6, mn.z + H * 0.5)
            cam.rotation_euler = (math.radians(90), 0, a)
            f = os.path.join(arg('--stress'), f'{NAME}_{pname}_{nm}.png'); outs.append(f)
            scene.render.filepath = f
            bpy.ops.render.render(write_still=True)
        for pb in ro.pose.bones: pb.matrix_basis = Matrix()
        bpy.context.view_layer.update()
    sys.exit(0)

# ------------------------------------------------------------------ kit region mask = clothing zone (skeleton) × cloth colour (texture)
gname = {g.index: g.name for g in obj.vertex_groups}
# ---- Neck / inside the V: Tripo often paints jersey colour onto skin above the collar. Find those vertices in 3D:
# kit-coloured and ABOVE the yellow collar trim at the same x (front or back side), so the V-neck itself is respected.
_nv = len(obj.data.vertices)
_uvd = obj.data.uv_layers.active.data; _vuv = np.zeros((_nv, 2))
for l_ in obj.data.loops: _vuv[l_.vertex_index] = _uvd[l_.index].uv
_th, _tw = tex_srgb.shape[:2]
_vpx = tex_srgb[np.clip((_vuv[:, 1] * _th).astype(int), 0, _th - 1), np.clip((_vuv[:, 0] * _tw).astype(int), 0, _tw - 1)]
_vmx = _vpx.max(1); _vmn = _vpx.min(1); _vsat = (_vmx - _vmn) / np.maximum(_vmx, 1e-6)
_vh = np.array([colorsys.rgb_to_hsv(*c)[0] for c in _vpx])
def _vhd(h0): d_ = np.abs(_vh - h0); return np.minimum(d_, 1 - d_)
V_ = np.array([v.co[:] for v in obj.data.vertices])
_redv = (np.minimum(_vhd(0.0), _vhd(_shirt_h)) < 0.06) & (_vsat > 0.35)
_kitv = (_vmx > 0.12) & (_redv | ((_vsat > 0.3) & ((_vhd(0.62) < 0.08) | (_vhd(0.37) < 0.08))))
_trimv = (_vsat > 0.35) & (_vmx > 0.35) & (_vhd(0.13) < 0.06) & (V_[:, 2] > Zf(0.7)) & (V_[:, 2] < Zf(0.9)) & (np.abs(V_[:, 0]) < 0.085 * H)   # collar only, never the sleeve cuffs
_nk = (V_[:, 2] > Zf(0.84)) & (V_[:, 2] < Zf(0.87)) & (np.abs(V_[:, 0]) < 0.05 * H)
_ny = float(np.median(V_[_nk, 1])) if _nk.any() else 0.0
neckv = np.zeros(_nv, bool)
_al = arm_label if len(arm_label) == _nv else np.zeros(_nv, np.int8)
if _trimv.sum() > 20:
    Tp = V_[_trimv]; Tfront = Tp[:, 1] < _ny
    for i in np.where(_kitv & (np.abs(V_[:, 0]) < 0.11 * H) & (V_[:, 2] > Zf(0.64)) & (V_[:, 2] < Zf(0.93)) & (_al == 0))[0]:
        x, y, z = V_[i]
        sel = (np.abs(Tp[:, 0] - x) < 0.012 * H) & (Tfront == (y < _ny))
        if sel.any() and z > Tp[sel, 2].max() + 0.004 * H: neckv[i] = True
_sk = (~_kitv) & (np.abs(V_[:, 0]) < 0.05 * H) & (V_[:, 2] > Zf(0.83)) & (V_[:, 2] < Zf(0.88)) & (V_[:, 1] < _ny) & (_vmx > 0.08)
neck_skin = np.median(_vpx[_sk], axis=0) if _sk.sum() > 5 else None
print('TRIPO neck-skin vertices', int(neckv.sum()), 'skin', None if neck_skin is None else np.round(neck_skin, 2))
km = obj.data.color_attributes.new(name='kitmask', type='FLOAT_COLOR', domain='POINT')
for v in obj.data.vertices:
    tot = sum(g.weight for g in v.groups) or 1
    hh = sum(g.weight for g in v.groups if gname.get(g.group) == 'head') / tot
    val = 1.0 - min(1.0, max(0.0, (hh - 0.15) / 0.25))
    if v.co.z > Zf(0.86): val = 0.0
    aw = sum(g.weight for g in v.groups if gname.get(g.group, '').startswith(('upperarm', 'forearm', 'hand'))) / tot
    shirt = 1.0 if (Zf(0.52) < v.co.z < Zf(0.80) and aw < 0.3) else 0.0   # torso: where A-pose arms hid the paint
    nw = sum(g.weight for g in v.groups if gname.get(g.group) in ('neck', 'head')) / tot
    km.data[v.index].color = (val, shirt, nw, 1)
mm = bpy.data.materials.new('maskbake'); mm.use_nodes = True
mt = mm.node_tree; mt.nodes.clear()
mo = mt.nodes.new('ShaderNodeOutputMaterial'); me_ = mt.nodes.new('ShaderNodeEmission'); vcn = mt.nodes.new('ShaderNodeVertexColor'); vcn.layer_name = 'kitmask'
mt.links.new(vcn.outputs['Color'], me_.inputs['Color']); mt.links.new(me_.outputs[0], mo.inputs['Surface'])
zimg = bpy.data.images.new('zone', T, T, alpha=False)
zn = mt.nodes.new('ShaderNodeTexImage'); zn.image = zimg; mt.nodes.active = zn
saved = list(obj.data.materials)
obj.data.materials.clear(); obj.data.materials.append(mm)
scene.render.engine = 'CYCLES'; scene.cycles.samples = 1; scene.cycles.device = 'CPU'
bpy.ops.object.select_all(action='DESELECT'); obj.select_set(True); bpy.context.view_layer.objects.active = obj
scene.render.bake.margin = 8
bpy.ops.object.bake(type='EMIT')
_zp = np.array(zimg.pixels[:], dtype=np.float32).reshape(T, T, 4); zone = _zp[:, :, 0]; shirtz = _zp[:, :, 1] > 0.5
neckW = _zp[:, :, 2]
# coverage: which texels belong to any UV island (margin 0) — mask growth may only fill empty space, never
# spill into a neighbouring face/eye/hair island
cv = obj.data.color_attributes.new(name='cov', type='FLOAT_COLOR', domain='POINT')
for i_ in range(len(cv.data)): cv.data[i_].color = (1, 1, 1, 1)
vcn.layer_name = 'cov'
cimg = bpy.data.images.new('cov', T, T, alpha=False); zn.image = cimg
scene.render.bake.margin = 0
bpy.ops.object.bake(type='EMIT')
cover = np.array(cimg.pixels[:], dtype=np.float32).reshape(T, T, 4)[:, :, 0] > 0.5
# per-texel 3D position (object space) — lets texture fixes be decided on the body, not across UV islands
tcn = mt.nodes.new('ShaderNodeTexCoord')
mt.links.new(tcn.outputs['Object'], me_.inputs['Color'])
pimg = bpy.data.images.new('pos', T, T, alpha=False, float_buffer=True); zn.image = pimg
bpy.ops.object.bake(type='EMIT')
P3 = np.array(pimg.pixels[:], dtype=np.float32).reshape(T, T, 4)[:, :, :3]
# texels physically above the collar trim (same x, same side), inside the collar's own width = neck skin zone
above_collar = np.zeros((T, T), bool)
if _trimv.sum() > 20:
    px, py, pz = P3[:, :, 0], P3[:, :, 1], P3[:, :, 2]
    for side in (True, False):
        tp = Tp[Tfront == side]
        if len(tp) < 8: continue
        xw = float(np.percentile(np.abs(tp[:, 0]), 95))
        bins = np.linspace(-xw, xw, 31); top = np.full(len(bins), np.nan)
        for k_, bx in enumerate(bins):
            sel = np.abs(tp[:, 0] - bx) < 0.012 * H
            if sel.any(): top[k_] = tp[sel, 2].max()
        ok_ = ~np.isnan(top)
        if ok_.sum() < 4: continue
        coll = np.interp(bins, bins[ok_], top[ok_])
        sm = cover & ((py < _ny) == side) & (np.abs(px) < xw + 0.004 * H) & (pz < Zf(0.855))   # neck only: below the chin, never hair
        idx = np.where(sm)
        hit = pz[sm] > np.interp(px[sm], bins, coll) + 0.004 * H
        above_collar[idx[0][hit], idx[1][hit]] = True
print('TRIPO above-collar texels', int(above_collar.sum()))
obj.data.materials.clear()
for m_ in saved: obj.data.materials.append(m_)

rgb = tex_srgb
mxc = rgb.max(2); mnc = rgb.min(2); dd = mxc - mnc
sat = dd / np.maximum(mxc, 1e-6)
hue = np.zeros_like(mxc); nz = dd > 1e-6
r_, g_, b_ = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
ir = nz & (mxc == r_); ig = nz & (mxc == g_) & ~ir; ib = nz & ~ir & ~ig
hue[ir] = ((g_ - b_)[ir] / dd[ir]) % 6; hue[ig] = (b_ - r_)[ig] / dd[ig] + 2; hue[ib] = (r_ - g_)[ib] / dd[ib] + 4
hue /= 6
def hdist(h0): d_ = np.abs(hue - h0); return np.minimum(d_, 1 - d_)
body = zone > 0.5
head = zone < 0.1
def med(sel, wrap=False):
    if sel.sum() < 30: return None
    h = hue[sel]
    if wrap: h = np.where(h > 0.5, h - 1, h)
    return [float(np.median(h)), float(np.median(sat[sel]))]
ok = (sat > 0.35) & (mxc > 0.2)
okc = (sat > 0.18) & (mxc > 0.12)   # shorts/socks: far from skin hue, so faded paint counts
cal = {'red': med(body & ok & (hdist(0.0) < 0.06), True), 'blue': med(body & ok & (hdist(0.62) < 0.1)),
       'green': med(body & okc & (hdist(0.37) < 0.1)), 'yellow': med(body & ok & (hdist(0.14) < 0.04)),
       'skin': med(head & (sat > 0.08) & (sat < 0.5) & (mxc > 0.5) & (hue < 0.12) & (hue > 0.02))}
json.dump(cal, open(os.path.join(OUT, NAME + '_kit.json'), 'w'))
print('TRIPO kit calibration', cal)
skin_h, skin_s = (cal['skin'] or [0.07, 0.3])
cloth = np.zeros_like(body)
for k, tol in (('red', 0.045), ('blue', 0.1), ('green', 0.1), ('yellow', 0.03)):
    if cal[k]:
        c = (okc if k in ('blue', 'green') else ok) & (hdist(cal[k][0] % 1.0) < tol)
        if k in ('red', 'yellow') and skin_s > 0.25: c &= hdist(skin_h) > 0.03
        cloth |= c
def dil(m, n):
    m = m.copy()
    for _ in range(n): m |= np.roll(m, 1, 0) | np.roll(m, -1, 0) | np.roll(m, 1, 1) | np.roll(m, -1, 1)
    return m
def ero(m, n):
    m = m.copy()
    for _ in range(n): m &= np.roll(m, 1, 0) & np.roll(m, -1, 0) & np.roll(m, 1, 1) & np.roll(m, -1, 1)
    return m
# Torso texels the A-pose arms covered were painted as dark smudges; they show as soon as an arm swings away.
# Inpaint dark / grey non-kit, non-skin texels on the torso from the surrounding shirt colour.
skinlike = (hdist(skin_h) < 0.05) & (sat > 0.12) & (mxc > 0.3)
trim = np.zeros_like(cloth)
if cal['yellow']: trim = ok & (hdist(cal['yellow'][0] % 1.0) < 0.05)
_v = mxc[shirtz & cloth]
print('TRIPO shirt value pct', [round(float(np.percentile(_v, q)), 3) for q in (1, 5, 10, 25, 50, 75)])
bad = shirtz & ~cloth & ~skinlike & ~trim & (mxc < 0.4) & ~above_collar   # dark arm-shadow smudges only; pale skin is not a smudge
good = shirtz & cloth & ~trim
# the kit paint is flat, so the shirt's median colour is the right fill (runtime recolour re-shades it anyway)
fill = np.broadcast_to(np.median(rgb[good], axis=0) if good.any() else np.array([0.8, 0.1, 0.1]), rgb.shape)
known = bad.copy()
print('TRIPO torso smudges inpainted', int((bad & known).sum()), 'texels; unreached', int((bad & ~known).sum()))
if (bad & known).any():
    rgb = np.where((bad & known)[:, :, None], fill, rgb)
    cloth |= bad & known
    lin = np.where(rgb <= 0.04045, rgb / 12.92, np.power((np.clip(rgb, 0, 1) + 0.055) / 1.055, 2.4)).astype(np.float32)
    Image_out = bpy.data.images.new('out2', lin.shape[1], lin.shape[0])
    Image_out.pixels[:] = np.dstack([lin, np.ones(lin.shape[:2], np.float32)]).ravel()
    Image_out.filepath_raw = tex_path; Image_out.file_format = 'PNG'; Image_out.save()
    subprocess.run(['sips', '-s', 'format', 'jpeg', '-s', 'formatOptions', '90', '-Z', '2048', tex_path, '--out', jpg], capture_output=True)
    os.remove(tex_path)
# Neck skin painted in jersey colour: repaint it with the character's own skin (keeping the painted shading).
_kitT = (mxc > 0.12) & (((sat > 0.3) & (np.minimum(hdist(0.0), hdist(_shirt_h)) < 0.07)) | ((sat > 0.28) & ((hdist(0.62) < 0.09) | (hdist(0.37) < 0.09))))
_rp = above_collar & _kitT
neckT = _rp.copy()
if neck_skin is not None and _rp.any():
    shade = np.clip(mxc[_rp] / max(float(neck_skin.max()), 1e-3), 0.65, 1.1)[:, None]
    rgb = rgb.copy(); rgb[_rp] = np.clip(neck_skin[None, :] * shade, 0, 1)
    lin = np.where(rgb <= 0.04045, rgb / 12.92, np.power((np.clip(rgb, 0, 1) + 0.055) / 1.055, 2.4)).astype(np.float32)
    Image_out = bpy.data.images.new('out3', lin.shape[1], lin.shape[0])
    Image_out.pixels[:] = np.dstack([lin, np.ones(lin.shape[:2], np.float32)]).ravel()
    Image_out.filepath_raw = tex_path; Image_out.file_format = 'PNG'; Image_out.save()
    subprocess.run(['sips', '-s', 'format', 'jpeg', '-s', 'formatOptions', '90', '-Z', '2048', tex_path, '--out', jpg], capture_output=True)
    os.remove(tex_path)
print('TRIPO neck texels repainted as skin', int(_rp.sum()))
cloth = dil(ero(cloth, 1), 2) & (zone > 0.3)
mask = (cloth.astype(np.float32) * np.clip(zone, 0, 1))
mask_in = mask.copy()
# Grow the mask past UV island borders so no unrecoloured texel survives at a seam (the 'faint lines')...
for _ in range(10):
    mask = np.maximum.reduce([mask, np.roll(mask, 1, 0), np.roll(mask, -1, 0), np.roll(mask, 1, 1), np.roll(mask, -1, 1)])
# Inside real islands the grown mask only lands on kit-looking texels (jersey shading the classifier missed);
# dark hair/beard or skin keeps the exact mask. Empty texture space keeps the full growth (seam lines).
_loose = (mxc > 0.15) & (sat > 0.15) & ((np.minimum(hdist(0.0), hdist(_shirt_h)) < 0.08) | (hdist(0.62) < 0.1) | (hdist(0.37) < 0.1) | (hdist(0.13) < 0.06))
_inside = cover & ~dil(~cover, 1)
mask = np.where(_inside & ~_loose, mask_in, mask)
# ...and never into head-zone texels (face, eyes, hair, beard) of a real island, nor the repainted neck.
mask[cover & (zone < 0.3)] = 0.0
mask[neckT | above_collar] = 0.0   # nothing above the collar is ever kit
# near the neck/shoulders, dark non-red texels are beard, dark skin, hijab or hair — never the (bright red) jersey
_dark_top = cover & (P3[:, :, 2] > Zf(0.74)) & (np.abs(P3[:, :, 0]) < 0.12 * H) & (mxc < 0.3) & (np.minimum(hdist(0.0), hdist(_shirt_h)) > 0.08)
mask[_dark_top] = 0.0
mask[dil(_dark_top & ~_kitT, 3)] = 0.0          # no blended fringe onto beards/dark skin after downsampling
# ...but never onto skin: pale skin's pinkish shadows sit near the jersey-red hue, and the runtime would repaint the
# neck/chin in the kit colour. Skin-like texels that aren't right at a cloth edge leave the mask.
skinish = (~cloth) & (sat < 0.42) & (mxc > 0.28) & ((hdist(skin_h) < 0.07) | (hdist(0.0) < 0.07) | (hdist(0.97) < 0.05))
# pale-skin shadows inside the V-neck read as pinkish jersey red: pull low-saturation bright reds out of the cloth
if skin_s < 0.3:
    _pink = cloth & (sat < 0.42) & (mxc > 0.62) & (hdist(0.0) < 0.07)
    cloth &= ~_pink; mask[_pink] = 0.0
    print('TRIPO pale-skin pinks removed from cloth', int(_pink.sum()))
_near_cloth = dil(cloth, 2)
_cut = skinish & ~_near_cloth
mask[_cut] = 0.0
print('TRIPO mask skin-guard cleared', int(_cut.sum()), 'texels')
if '--chindbg' in A:
    r_ = cover & _kitT & (P3[:, :, 2] > Zf(0.77)) & (P3[:, :, 2] < Zf(0.86)) & (np.abs(P3[:, :, 0]) < 0.1 * H) & ~above_collar
    ys_, xs_ = np.nonzero(r_)
    print('CHINDBG kit texels near neck NOT above collar', len(ys_))
    if len(ys_):
        pp = P3[ys_, xs_]
        H2, xe, ze = np.histogram2d(pp[:, 0] / H, (pp[:, 2] - mn.z) / H, bins=[8, 6])
        print('x bins', np.round(xe, 3)); print('z bins', np.round(ze, 3)); print(H2.astype(int))
        print('front frac', float((pp[:, 1] < _ny).mean()), 'trim n', len(Tp), 'trim x range %.3f..%.3f z %.3f..%.3f' % (Tp[:, 0].min() / H, Tp[:, 0].max() / H, (Tp[:, 2].min() - mn.z) / H, (Tp[:, 2].max() - mn.z) / H))
mimg = bpy.data.images.new('mask', T, T, alpha=False)
mimg.pixels[:] = np.dstack([mask, mask, mask, np.ones_like(mask)]).ravel()
mask_path = os.path.join(OUT, NAME + '_mask.png')
mimg.filepath_raw = mask_path; mimg.file_format = 'PNG'; mimg.save()
subprocess.run(['sips', '-Z', '2048', '-s', 'format', 'png', '-m', '/System/Library/ColorSync/Profiles/Generic Gray Profile.icc', mask_path], capture_output=True)
print('TRIPO kit mask', mask_path, 'cloth texels', int(cloth.sum()))

# ------------------------------------------------------------------ export (same binary format as base.bin)
C = Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, -1, 0, 0), (0, 0, 0, 1)))
def to_scn(v): return [round(v[0], 5), round(v[2], 5), round(-v[1], 5)]
names = [b.name for b in arm.bones]
bones = []
for b in arm.bones:
    m = C @ b.matrix_local @ C.transposed()
    bones.append({'name': b.name, 'parent': names.index(b.parent.name) if b.parent else -1,
                  'matrix': [round(m[r][c], 6) for c in range(4) for r in range(4)]})
me = obj.data.copy()
bm = bmesh.new(); bm.from_mesh(me); bmesh.ops.triangulate(bm, faces=bm.faces[:]); bm.to_mesh(me); bm.free()
uvl = me.uv_layers.active
groups = {g.index: g.name for g in obj.vertex_groups}
positions, normals, uvs, joints, weights, tris = [], [], [], [], [], []
index_of = {}
cn = me.corner_normals if hasattr(me, 'corner_normals') else None
for poly in me.polygons:
    for li in poly.loop_indices:
        vi = me.loops[li].vertex_index
        nrm = cn[li].vector if cn is not None else me.vertices[vi].normal
        uv = tuple(uvl.data[li].uv)
        key = (vi, round(uv[0], 5), round(uv[1], 5))
        if key not in index_of:
            index_of[key] = len(positions)
            positions.append(to_scn(me.vertices[vi].co)); normals.append(to_scn(nrm.normalized()))
            uvs.append([round(uv[0], 5), round(1 - uv[1], 5)])
            ws = sorted(((g.weight, names.index(groups[g.group])) for g in me.vertices[vi].groups if groups.get(g.group) in names and g.weight > 0.001), reverse=True)[:4]
            tot = sum(w for w, _ in ws) or 1
            ws = [(w / tot, b) for w, b in ws] + [(0, 0)] * (4 - len(ws))
            joints.append([b for _, b in ws]); weights.append([round(w, 4) for w, _ in ws])
        tris.append(index_of[key])
blob = bytearray()
def put(fmt, a):
    off = len(blob); blob.extend(struct.pack('<%d%s' % (len(a), fmt), *a))
    while len(blob) % 4: blob.append(0)
    return off
flat = lambda a: [c for x in a for c in x]
n = len(positions)
idx_fmt = 'H' if n < 65535 else 'I'
meta = [{'name': NAME, 'slot': 'unique', 'count': n, 'pos': put('f', flat(positions)), 'nor': put('f', flat(normals)), 'uv': put('f', flat(uvs)),
         'joints': put('H', flat(joints)), 'weights': put('f', flat(weights)),
         'groups': [{'material': 'unique', 'offset': put(idx_fmt, tris), 'count': len(tris)}], 'index32': idx_fmt == 'I'}]
header = json.dumps({'version': 2, 'bones': bones, 'meshes': meta, 'headCenter': to_scn([0, mn.z + 0.905 * H, 0]), 'headRadius': 0.09 * H, 'outline': False}, separators=(',', ':')).encode()
while (4 + len(header)) % 4: header += b' '
dest = os.path.join(OUT, NAME + '.bin')
with open(dest, 'wb') as f:
    f.write(struct.pack('<I', len(header))); f.write(header); f.write(blob)
print('TRIPO exported', dest, os.path.getsize(dest), 'bytes', n, 'verts', len(tris) // 3, 'tris')

# ------------------------------------------------------------------ preview
if '--preview' in A:
    obj.data.materials.clear()
    pm = bpy.data.materials.new('prev'); pm.use_nodes = True
    t = pm.node_tree; t.nodes.clear()
    o2 = t.nodes.new('ShaderNodeOutputMaterial'); e = t.nodes.new('ShaderNodeEmission'); ti = t.nodes.new('ShaderNodeTexImage')
    ti.image = tex; t.links.new(ti.outputs[0], e.inputs[0]); t.links.new(e.outputs[0], o2.inputs[0])
    obj.data.materials.append(pm)
    ro.hide_render = True
    scene.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in [x.identifier for x in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items] else 'BLENDER_EEVEE'
    scene.render.resolution_x, scene.render.resolution_y = 700, 1000
    w = bpy.data.worlds.new('w'); scene.world = w; w.color = (0.25, 0.25, 0.28)
    cd = bpy.data.cameras.new('c'); cd.type = 'ORTHO'; cd.ortho_scale = H * 1.15
    cam = bpy.data.objects.new('c', cd); scene.collection.objects.link(cam); scene.camera = cam
    for nm, deg in (('front', 0), ('34', 40), ('side', 90), ('back', 180)):
        a = math.radians(deg)
        cam.location = (math.sin(a) * 6, -math.cos(a) * 6, mn.z + H * 0.52)
        cam.rotation_euler = (math.radians(90), 0, a)
        scene.render.filepath = os.path.join(ROOT, 'art', 'tripo', f'{NAME}_prev_{nm}.png')
        bpy.ops.render.render(write_still=True)
    cd.ortho_scale = H * 0.3
    scene.render.resolution_x, scene.render.resolution_y = 600, 600
    for nm, deg in (('front', 0), ('34', 40)):
        a = math.radians(deg)
        cam.location = (math.sin(a) * 6, -math.cos(a) * 6, mn.z + H * 0.85)
        cam.rotation_euler = (math.radians(90), 0, a)
        scene.render.filepath = os.path.join(ROOT, 'art', 'tripo', f'{NAME}_head_{nm}.png')
        bpy.ops.render.render(write_still=True)
