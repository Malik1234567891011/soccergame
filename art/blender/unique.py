"""
Unique-character builder: AI image-to-3D mesh + multi-view model-sheet projection → rigged, textured game model.
  Blender -b -P art/blender/unique.py -- --mesh luna.glb --front f.png --back b.png --left l.png --right r.png --name luna [--preview]

Views (character faces -Y in Blender):
  front: viewer at -Y   back: viewer at +Y   left: viewer at +X (character faces image-right)   right: viewer at -X
Output: Panna/Resources/Characters/<name>.bin (same binary format as base.bin, one mesh slot "unique")
        Panna/Resources/Characters/<name>.jpg (baked projection texture)
"""
import bpy, bmesh, math, json, sys, os, struct
import numpy as np
from mathutils import Vector, Matrix

A = sys.argv[sys.argv.index('--') + 1:]
def arg(k, d=None):
    return A[A.index(k) + 1] if k in A else d
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
NAME = arg('--name', 'unique')
HEIGHT = float(arg('--height', '1.9'))
TRIS = int(arg('--tris', '22000'))
TEX = int(arg('--tex', '2048'))

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

# ------------------------------------------------------------------ mesh
bpy.ops.import_scene.gltf(filepath=os.path.abspath(arg('--mesh')))
meshes = [o for o in scene.objects if o.type == 'MESH']
bpy.ops.object.select_all(action='DESELECT')
for o in meshes: o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1: bpy.ops.object.join()
obj = bpy.context.active_object
obj.parent = None
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in list(scene.objects):
    if o != obj: bpy.data.objects.remove(o)
obj.data.materials.clear()

def bbox(o):
    vs = [v.co for v in o.data.vertices]
    mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return mn, mx

mn, mx = bbox(obj)
s = HEIGHT / (mx.z - mn.z)
ctr = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))
for v in obj.data.vertices:
    v.co = (v.co - ctr) * s
n0 = len(obj.data.polygons)
dec = obj.modifiers.new('dec', 'DECIMATE'); dec.ratio = min(1.0, TRIS / max(1, n0))
bpy.context.view_layer.objects.active = obj; obj.select_set(True)
bpy.ops.object.modifier_apply(modifier='dec')
for p in obj.data.polygons: p.use_smooth = True
mn, mx = bbox(obj)
print('UNIQUE mesh', n0, '->', len(obj.data.polygons), 'faces; bbox', tuple(mn), tuple(mx))

# ------------------------------------------------------------------ face smoothing
# The generator sculpts bumps where eyes/brows/mouth are drawn. Anime faces are smooth: relax the front of the
# face so the painted features project cleanly instead of smearing over ridges and pits.
Hh = mx.z - mn.z
obj.data.calc_normals_split() if hasattr(obj.data, 'calc_normals_split') else None
nbr = [[] for _ in obj.data.vertices]
for e in obj.data.edges:
    a, b = e.vertices; nbr[a].append(b); nbr[b].append(a)
face_band = [v for v in obj.data.vertices if mn.z + 0.87 * Hh < v.co.z < mn.z + 0.95 * Hh]
hw_face = sorted(abs(v.co.x) for v in face_band)[int(len(face_band) * 0.85)] if face_band else 0.1
fw = {}
for v in obj.data.vertices:
    zf = (v.co.z - mn.z) / Hh
    if not (0.85 < zf < 0.965): continue
    if v.normal.y > -0.25: continue
    wz = min(1.0, (zf - 0.85) / 0.02, (0.965 - zf) / 0.02)
    wx = max(0.0, min(1.0, (hw_face * 0.85 - abs(v.co.x)) / (hw_face * 0.25)))
    wn = min(1.0, (-v.normal.y - 0.25) / 0.3)
    w = wz * wx * wn
    if w > 0.01: fw[v.index] = w
co = [v.co.copy() for v in obj.data.vertices]
for _ in range(10):
    nc = list(co)
    for i, w in fw.items():
        if nbr[i]:
            avg = sum((co[j] for j in nbr[i]), Vector()) / len(nbr[i])
            nc[i] = co[i] + (avg - co[i]) * 0.5 * w
    co = nc
for i in fw: obj.data.vertices[i].co = co[i]
obj.data.update()
print('UNIQUE face smoothed', len(fw), 'verts')

# ------------------------------------------------------------------ UVs
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004)
# Faces and hair are what players look at: give head islands ~2.5x the texel density, then repack.
bm_uv = bmesh.from_edit_mesh(obj.data)
uvl = bm_uv.loops.layers.uv.verify()
z_head = mn.z + 0.845 * (mx.z - mn.z)
seen = set()
for f in bm_uv.faces:
    if f.index in seen: continue
    # flood the UV island (faces sharing UV-coincident edges)
    isl = [f]; seen.add(f.index); stack = [f]
    while stack:
        g = stack.pop()
        for e in g.edges:
            for h in e.link_faces:
                if h.index in seen: continue
                ok = True
                for v in e.verts:
                    a = next(l[uvl].uv for l in g.loops if l.vert == v)
                    b = next(l[uvl].uv for l in h.loops if l.vert == v)
                    if (a - b).length > 1e-5: ok = False; break
                if ok: seen.add(h.index); isl.append(h); stack.append(h)
    zc = sum(f_.calc_center_median().z for f_ in isl) / len(isl)
    if zc > z_head:
        loops = [l for f_ in isl for l in f_.loops]
        c = sum((l[uvl].uv for l in loops), Vector((0, 0))) / len(loops)
        for l in loops: l[uvl].uv = c + (l[uvl].uv - c) * 2.5
bmesh.update_edit_mesh(obj.data)
bpy.ops.uv.select_all(action='SELECT')
bpy.ops.uv.pack_islands(rotate=True, margin=0.004)
bpy.ops.object.mode_set(mode='OBJECT')

# ------------------------------------------------------------------ views
def load_view(path, keep_face=False):
    img = bpy.data.images.load(os.path.abspath(path))
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)  # bottom-up rows
    # Paper-grain sheets: an edge-preserving 3x3 median kills the grain (which speckles recolours and skin)
    # while keeping line art crisp. Clean sheets are left untouched.
    corner = px[:24, :24, :3].reshape(-1, 3)
    if float(np.abs(corner - np.median(corner, 0)).sum(1).mean()) > 0.018:
        for _ in range(2):
            stack = np.stack([np.roll(np.roll(px[:, :, :3], dy, 0), dx, 1) for dy in (-1, 0, 1) for dx in (-1, 0, 1)], 0)
            px[:, :, :3] = np.median(stack, 0)
        print('VIEW', os.path.basename(path), 'grain removed')
    bg = np.median(np.concatenate([px[:8, :8, :3].reshape(-1, 3), px[-8:, -8:, :3].reshape(-1, 3), px[:8, -8:, :3].reshape(-1, 3)]), axis=0)
    diff = np.abs(px[:, :, :3] - bg).sum(axis=2)
    # Background = bg-coloured pixels connected to the image border. Enclosed pale areas (eye whites, silver
    # hair, highlights) are figure even when they match the backdrop colour.
    # Paper-textured backdrops: compare a lightly blurred image, with a threshold scaled to the backdrop grain.
    def _box3(a, r=2):
        c = np.cumsum(np.cumsum(np.pad(a, ((r + 1, r), (r + 1, r)), mode='edge'), 0), 1)
        k = 2 * r + 1
        return (c[k:, k:] - c[:-k, k:] - c[k:, :-k] + c[:-k, :-k]) / (k * k)
    blur = np.stack([_box3(px[:, :, k]) for k in range(3)], 2)
    dblur = np.abs(blur - bg).sum(axis=2)
    corners = np.concatenate([dblur[:24, :24].ravel(), dblur[-24:, -24:].ravel(), dblur[:24, -24:].ravel(), dblur[-24:, :24].ravel()])
    thr = max(0.12, float(np.percentile(corners, 99)) * 1.6)
    sim = dblur <= thr
    reach = np.zeros_like(sim)
    reach[0, :] = sim[0, :]; reach[-1, :] = sim[-1, :]; reach[:, 0] = sim[:, 0]; reach[:, -1] = sim[:, -1]
    def sweep(reach, axis):
        s_ = sim if axis == 1 else sim.T
        r_ = reach if axis == 1 else reach.T
        run = np.cumsum(~s_, axis=1) + np.arange(s_.shape[0])[:, None] * (s_.shape[1] + 1)
        ids = np.unique(run[r_ & s_])
        out = s_ & np.isin(run, ids)
        return out if axis == 1 else out.T
    for _ in range(40):
        nr = sweep(sweep(reach, 1), 0)
        if (nr == reach).all(): break
        reach = nr
    mask = ~reach
    ys, xs = np.nonzero(mask)
    def erode(m, n):
        m = m.copy()
        for _ in range(n): m &= np.roll(m, 1, 0) & np.roll(m, -1, 0) & np.roll(m, 1, 1) & np.roll(m, -1, 1)
        return m
    def dilate(m, n):
        m = m.copy()
        for _ in range(n): m |= np.roll(m, 1, 0) | np.roll(m, -1, 0) | np.roll(m, 1, 1) | np.roll(m, -1, 1)
        return m
    def box(a, r):
        c = np.cumsum(np.cumsum(np.pad(a, ((r + 1, r), (r + 1, r)), mode='edge'), 0), 1)
        k = 2 * r + 1
        return (c[k:, k:] - c[:-k, k:] - c[k:, :-k] + c[:-k, :-k]) / (k * k)
    # Strip line art: strokes clearly darker than their surroundings (outlines, muscle/fold lines) are drawing,
    # not surface colour. Thick dark regions (hair, boots, eyes) stay. Anti-aliased fringes go with them.
    lum = px[:, :, 0] * 0.3 + px[:, :, 1] * 0.59 + px[:, :, 2] * 0.11
    ink = ((lum < 0.2) | (lum < box(lum, 6) - 0.08)) & mask
    thick = dilate(erode(ink, 3), 3) & (lum < 0.2)
    thin = dilate(ink & ~thick, 1)
    if keep_face:
        # Faces are line art: keep every stroke in the head (top ~17% of the figure).
        ys_, xs_ = np.nonzero(mask)
        top_row = ys_.max(); fig_h = ys_.max() - ys_.min()
        head_rows = slice(int(top_row - 0.17 * fig_h), int(top_row) + 1)
        thin[head_rows, :] = False
    # Silhouette edges carry outline ink and background bleed: drop a 6px rim.
    fill_mask = erode(mask, 6) & ~thin
    # rows are bottom-up: convert to top-down pixel coords
    top = h - 1 - ys.max(); bottom = h - 1 - ys.min()
    left = xs.min(); right = xs.max()
    # Fill the holes and grow figure colours outward with a multi-scale normalised blur (no directional streaks).
    # Fill per colour class (code-kit cloth vs everything else) so a gap between arm and shirt never becomes a
    # skin/shirt blend: each empty pixel takes the class that dominates around it.
    col = px.copy()
    rr, gg, bb_ = px[:, :, 0], px[:, :, 1], px[:, :, 2]
    mx_ = np.maximum(np.maximum(rr, gg), bb_); mn_ = np.minimum(np.minimum(rr, gg), bb_); d_ = mx_ - mn_
    sat_ = d_ / np.maximum(mx_, 1e-6)
    hue_ = np.zeros_like(mx_)
    nz = d_ > 1e-6
    i_r = nz & (mx_ == rr); i_g = nz & (mx_ == gg) & ~i_r; i_b = nz & ~i_r & ~i_g
    hue_[i_r] = ((gg - bb_)[i_r] / d_[i_r]) % 6; hue_[i_g] = (bb_ - rr)[i_g] / d_[i_g] + 2; hue_[i_b] = (rr - gg)[i_b] / d_[i_b] + 4
    hue_ /= 6
    kitc = (sat_ > 0.3) & ((hue_ < 0.035) | (hue_ > 0.93) | (np.abs(hue_ - 0.14) < 0.05) | (np.abs(hue_ - 0.63) < 0.12) | (np.abs(hue_ - 0.37) < 0.12) | (sat_ > 0.62))
    classes = [fill_mask & kitc, fill_mask & ~kitc]
    filled_any = fill_mask.copy()
    for r in (1, 2, 3, 5, 8, 12, 20, 32, 48):
        dens, nums = [], []
        for cm in classes:
            mf = cm.astype(np.float32)
            dens.append(box(mf, r)); nums.append([box(col[:, :, k] * mf, r) for k in range(3)])
        todo = ~filled_any & ((dens[0] > 1e-3) | (dens[1] > 1e-3))
        pick0 = dens[0] >= dens[1]
        for ci, sel_ in ((0, todo & pick0), (1, todo & ~pick0)):
            for k in range(3):
                ch = col[:, :, k]; ch[sel_] = nums[ci][k][sel_] / np.maximum(dens[ci][sel_], 1e-6)
            classes[ci] = classes[ci] | sel_
        filled_any |= todo
    img.pixels[:] = col.ravel()
    img.update()
    view_px[os.path.abspath(path)] = col
    print('VIEW', os.path.basename(path), 'figure px x', left, right, 'y', top, bottom)
    return img, (float(w), float(h), float(left), float(right), float(top), float(bottom)), mask

def kit_calibration(col, mask):
    """Measure this sheet's own code-kit hues (jersey, shorts, socks) and skin, so the runtime recolour
    can be tight per character. col/mask are bottom-up arrays from load_view."""
    import colorsys
    ys, xs = np.nonzero(mask)
    y0, y1 = ys.min(), ys.max(); H_ = y1 - y0
    xc = (xs.min() + xs.max()) / 2; W_ = xs.max() - xs.min()
    def band(f0, f1, wx, pred):
        r0, r1 = int(y0 + f0 * H_), int(y0 + f1 * H_)
        sub = col[r0:r1, int(xc - wx * W_):int(xc + wx * W_), :3].reshape(-1, 3)
        m = mask[r0:r1, int(xc - wx * W_):int(xc + wx * W_)].reshape(-1)
        hs = []
        for c in sub[m][::7]:
            h, s_, v = colorsys.rgb_to_hsv(*c)
            if pred(h, s_, v): hs.append((h, s_, v))
        return hs
    def med(hs, wrap=False):
        if not hs: return None
        h = np.array([x[0] for x in hs])
        if wrap: h = np.where(h > 0.5, h - 1, h)
        return float(np.median(h)), float(np.median([x[1] for x in hs]))
    red = med(band(0.62, 0.72, 0.12, lambda h, s_, v: s_ > 0.45 and v > 0.25 and (h < 0.1 or h > 0.9)), wrap=True)
    blue = med(band(0.44, 0.52, 0.12, lambda h, s_, v: s_ > 0.35 and 0.5 < h < 0.8))
    green = med(band(0.06, 0.22, 0.3, lambda h, s_, v: s_ > 0.3 and 0.2 < h < 0.55))
    skin = med(band(0.86, 0.9, 0.05, lambda h, s_, v: s_ > 0.15 and v > 0.12 and h < 0.15))
    # Trim (collar / cuffs): the golden-yellow cluster on the upper torso and sleeves.
    yellow = med(band(0.7, 0.8, 0.3, lambda h, s_, v: s_ > 0.45 and v > 0.4 and 0.085 < h < 0.19))
    if yellow and abs(yellow[0] - 0.14) > 0.045: yellow = None   # that was hair, not trim
    return {'red': red, 'blue': blue, 'green': green, 'skin': skin, 'yellow': yellow}

views = {}
view_px = {}
view_cloth = {}
for k in ('front', 'back', 'left', 'right'):
    p = arg('--' + k)
    if p: views[k] = load_view(p, keep_face=(k != 'back'))
if 'front' in views:
    _cal = kit_calibration(view_px[os.path.abspath(arg('--front'))], views['front'][2])
    _calp = os.path.join(ROOT, 'Panna', 'Resources', 'Characters', NAME + '_kit.json')
    json.dump(_cal, open(_calp, 'w'))
    print('UNIQUE kit calibration', _cal)

def build_cloth(key, cal):
    """Cloth map for the runtime recolour: this sheet's own jersey/trim/shorts/sock hues on a smoothed image
    (paper grain never counts), plus thin seams where two kit colours blend. Skin never qualifies."""
    img, (w, h, l, r, t, b), mask = views[key]
    col = view_px[os.path.abspath(arg('--' + key))][:, :, :3]
    def box(a_, r_=2):
        c_ = np.cumsum(np.cumsum(np.pad(a_, ((r_ + 1, r_), (r_ + 1, r_)), mode='edge'), 0), 1)
        k_ = 2 * r_ + 1
        return (c_[k_:, k_:] - c_[:-k_, k_:] - c_[k_:, :-k_] + c_[:-k_, :-k_]) / (k_ * k_)
    sm = np.stack([box(col[:, :, i]) for i in range(3)], 2)
    mx_ = sm.max(2); mn_ = sm.min(2); d_ = mx_ - mn_
    sat = d_ / np.maximum(mx_, 1e-6)
    hue = np.zeros_like(mx_); nz = d_ > 1e-6
    ir = nz & (mx_ == sm[:, :, 0]); ig = nz & (mx_ == sm[:, :, 1]) & ~ir; ib = nz & ~ir & ~ig
    hue[ir] = ((sm[:, :, 1] - sm[:, :, 2])[ir] / d_[ir]) % 6; hue[ig] = (sm[:, :, 2] - sm[:, :, 0])[ig] / d_[ig] + 2; hue[ib] = (sm[:, :, 0] - sm[:, :, 1])[ib] / d_[ib] + 4
    hue /= 6
    redh = (cal.get('red') or (0.0, 0))[0]; skin = cal.get('skin') or (0.07, 0.3)
    tol = max(0.012, min(0.035, (skin[0] - redh) * 0.5)) if skin[1] > 0.45 else 0.035
    dr = np.abs(hue - (redh % 1.0)); dr = np.minimum(dr, 1 - dr)
    ok = (sat > 0.4) & (mx_ > 0.12)
    red = ok & (dr < tol)
    yh = (cal.get('yellow') or (0.14, 0))[0]
    yel = (sat > 0.3) & (mx_ > 0.3) & (np.abs(hue - yh) < 0.035)
    blu = (sat > 0.25) & (mx_ > 0.08) & (np.abs(hue - ((cal.get('blue') or (0.63, 0))[0])) < 0.12)
    grn = (sat > 0.25) & (mx_ > 0.08) & (np.abs(hue - ((cal.get('green') or (0.37, 0))[0])) < 0.14)
    def dil(m_, n):
        m_ = m_.copy()
        for _ in range(n): m_ |= np.roll(m_, 1, 0) | np.roll(m_, -1, 0) | np.roll(m_, 1, 1) | np.roll(m_, -1, 1)
        return m_
    def ero(m_, n):
        m_ = m_.copy()
        for _ in range(n): m_ &= np.roll(m_, 1, 0) & np.roll(m_, -1, 0) & np.roll(m_, 1, 1) & np.roll(m_, -1, 1)
        return m_
    kit = red | yel | blu | grn
    seam = (sat > 0.45) & ~kit & ((dil(red, 4) & dil(yel, 4)) | (dil(red, 4) & dil(blu, 4)))
    cloth = dil(ero(kit | seam, 2), 2) & mask       # opening: speckle never survives
    view_cloth[os.path.abspath(arg('--' + key))] = cloth.astype(np.float32)
for _k in ('front', 'back'):
    if _k in views: build_cloth(_k, _cal)

def register_vertical(key):
    """Refine vertical scale/offset of a front/back view by matching silhouette width profiles to the mesh."""
    img, (w, h, l, r, t, b), mask = views[key]
    hh = int(h)
    rows_w = np.zeros(hh)
    for row in range(hh):
        idx = np.nonzero(mask[hh - 1 - row])[0]
        if len(idx): rows_w[row] = idx.max() - idx.min()
    zs = np.linspace(zmin, zmax, 240)
    vx = np.array([v.co.x for v in obj.data.vertices]); vz = np.array([v.co.z for v in obj.data.vertices])
    mesh_w = np.zeros(len(zs))
    dz = (zmax - zmin) / 240
    for i, z in enumerate(zs):
        sel = vx[np.abs(vz - z) < dz]
        if len(sel): mesh_w[i] = sel.max() - sel.min()
    ppm0 = (b - t) / (zmax - zmin)
    best = (1e18, ppm0, t)
    for sc in np.linspace(0.9, 1.1, 41):
        ppm = ppm0 * sc
        for off in np.linspace(-0.06, 0.06, 49):
            tt = t + off * (b - t)
            rows = ((zmax - zs) * ppm + tt).astype(int)
            ok = (rows >= 0) & (rows < hh)
            if ok.sum() < 150: continue
            diff = np.abs(rows_w[rows[ok]] - mesh_w[ok] * ppm)
            cost = diff.mean()
            if cost < best[0]: best = (cost, ppm, tt)
    _, ppm, tt = best
    nb = tt + ppm * (zmax - zmin)
    print('REGISTER', key, 'scale', round(ppm / ppm0, 3), 'offset px', round(tt - t, 1))
    views[key] = (img, (w, h, l, r, tt, nb), mask)

head_map = {}
def register_head(key, z0f=0.845):
    """Heads rarely match the drawing's proportions: fit a separate x/z affine map for the head band by
    matching the head silhouette (row extents) of the image to the mesh."""
    img, (w, h, l, r, t, b), mask = views[key]
    hh = int(h)
    ext = np.full((hh, 2), np.nan)
    for row in range(hh):
        idx = np.nonzero(mask[hh - 1 - row])[0]
        if len(idx): ext[row] = (idx.min(), idx.max())
    z0 = zmin + z0f * (zmax - zmin)
    axis = 'x' if key in ('front', 'back') else 'y'
    vx = np.array([getattr(v.co, axis) for v in obj.data.vertices]); vz = np.array([v.co.z for v in obj.data.vertices])
    zs = np.linspace(z0, zmax, 48); dz = (zmax - z0) / 48
    mesh = []
    for z in zs:
        sel = vx[np.abs(vz - z) < dz * 0.75]
        if len(sel) >= 2: mesh.append((z, sel.min(), sel.max()))
    mesh = np.array(mesh)
    ppm = (b - t) / (zmax - zmin)
    sign = (1 if key == 'front' else -1) if axis == 'x' else (-1 if dirs[key] > 0 else 1)
    headpx = (zmax - z0) * ppm
    best = None
    for sz in np.linspace(0.88, 1.12, 25):
        for off in np.linspace(-0.25, 0.25, 41):
            D = -ppm * sz
            C = t + zmax * ppm * sz + off * headpx
            rows = np.round(C + D * mesh[:, 0]).astype(int)
            ok = (rows >= 0) & (rows < hh)
            ex = np.full((len(rows), 2), np.nan); ex[ok] = ext[rows[ok]]
            good = ~np.isnan(ex[:, 0])
            miss = (~good).sum()
            if good.sum() < 10: continue
            xm = np.concatenate([mesh[good, 1], mesh[good, 2]]) if sign > 0 else np.concatenate([mesh[good, 2], mesh[good, 1]])
            ui = np.concatenate([ex[good, 0], ex[good, 1]])
            Bm, Am = np.polyfit(xm, ui, 1)
            if not (0.85 <= Bm / (sign * ppm) <= 1.2): continue
            cost = np.abs(ui - (Am + Bm * xm)).mean() + miss * 3.0 + 25 * abs(off) + 25 * abs(sz - 1)
            if best is None or cost < best[0]: best = (cost, Am, Bm, C, D, sz, off)
    if best is None or os.environ.get('NO_HEADFIT'): return
    cost, A, B, C, D, sz, off = best
    head_map[key] = (float(A), float(B), float(C), float(D))
    print('HEAD REGISTER', key, 'xscale', round(B / (sign * ppm), 3), 'zscale', round(sz, 3), 'zoff', round(off, 3), 'cost', round(cost, 2))

def facing(mask, h, top, bottom):
    """+1 if the profile faces image-right, -1 if image-left (boots point forward past the calf)."""
    def centre(f0, f1):
        xs = []
        for r in range(int(bottom - f1 * (bottom - top)), int(bottom - f0 * (bottom - top))):
            idx = np.nonzero(mask[h - 1 - r])[0]
            if len(idx): xs.append((idx.min() + idx.max()) / 2)
        return float(np.median(xs)) if xs else 0.0
    return 1 if centre(0.0, 0.035) > centre(0.12, 0.22) else -1

# Side views: work out which side each really shows; mirror one if both show the same side.
side_keys = [k for k in ('left', 'right') if k in views]
dirs = {}
for k in side_keys:
    img, dims, mask = views[k]
    dirs[k] = facing(mask, int(dims[1]), dims[4], dims[5])
    print('FACING', k, 'image-right' if dirs[k] > 0 else 'image-left')
if len(side_keys) == 1:
    k0 = side_keys[0]
    img0, (w, h, l, r, t, b), mask0 = views[k0]
    twin = img0.copy()
    px = np.array(img0.pixels[:], dtype=np.float32).reshape(int(h), int(w), 4)[:, ::-1, :].copy()
    twin.pixels[:] = px.ravel(); twin.update()
    other = 'right' if k0 == 'left' else 'left'
    views[other] = (twin, (w, h, w - 1 - r, w - 1 - l, t, b), mask0[:, ::-1].copy())
    dirs[other] = -dirs[k0]
    print('MIRRORED single side view to cover both sides')
elif len(side_keys) == 2 and dirs['left'] == dirs['right']:
    img, (w, h, l, r, t, b), mask = views['right']
    px = np.array(img.pixels[:], dtype=np.float32).reshape(int(h), int(w), 4)[:, ::-1, :].copy()
    img.pixels[:] = px.ravel(); img.update()
    views['right'] = (img, (w, h, w - 1 - r, w - 1 - l, t, b), mask[:, ::-1].copy())
    dirs['right'] = -dirs['left']
    print('MIRRORED right view to cover the other side')

def band_center_img(mask, h, top, bottom, f0, f1):
    """Horizontal centre of the figure in a height band (fractions from the feet up)."""
    rows_td = range(int(bottom - f1 * (bottom - top)), int(bottom - f0 * (bottom - top)))
    xs = []
    for r in rows_td:
        row = mask[h - 1 - r]
        idx = np.nonzero(row)[0]
        if len(idx): xs.append((idx.min() + idx.max()) / 2)
    return float(np.median(xs)) if xs else None

def band_center_mesh(axis, f0, f1):
    z0, z1 = mn.z + f0 * (mx.z - mn.z), mn.z + f1 * (mx.z - mn.z)
    vals = [getattr(v.co, axis) for v in obj.data.vertices if z0 <= v.co.z <= z1]
    return (min(vals) + max(vals)) / 2 if vals else 0.0

# ------------------------------------------------------------------ per-vertex visibility (occlusion-aware projection)
from mathutils.bvhtree import BVHTree
bm_vis = bmesh.new(); bm_vis.from_mesh(obj.data); bm_vis.verts.ensure_lookup_table()
bvh = BVHTree.FromBMesh(bm_vis)
view_dirs = [Vector((0, -1, 0)), Vector((0, 1, 0)), Vector((-1, 0, 0)), Vector((1, 0, 0))]  # front, back, -X, +X
vis_layer = obj.data.color_attributes.new(name='vis', type='FLOAT_COLOR', domain='POINT')
vals = [[0.0, 0.0, 0.0, 0.0] for _ in obj.data.vertices]
for c, d in enumerate(view_dirs):
    for v in obj.data.vertices:
        hit = bvh.ray_cast(v.co + v.normal * 0.004 + d * 0.002, d, 5.0)
        vals[v.index][c] = 0.0 if hit[0] is not None else 1.0
adj = [[] for _ in obj.data.vertices]
for e in obj.data.edges:
    a, b = e.vertices; adj[a].append(b); adj[b].append(a)
for _ in range(2):
    nv = [list(x) for x in vals]
    for i, ns in enumerate(adj):
        for c in range(4):
            if vals[i][c] > 0 and any(vals[j][c] == 0 for j in ns): nv[i][c] = 0.3
    vals = nv
for i, v4 in enumerate(vals): vis_layer.data[i].color = v4
bm_vis.free()
print('UNIQUE visibility computed')

# ------------------------------------------------------------------ projection material
mat = bpy.data.materials.new('proj')
mat.use_nodes = True
nt = mat.node_tree
nodes, links = nt.nodes, nt.links
nodes.clear()
out = nodes.new('ShaderNodeOutputMaterial')
emit = nodes.new('ShaderNodeEmission')
links.new(emit.outputs[0], out.inputs['Surface'])
texco = nodes.new('ShaderNodeTexCoord')
geom = nodes.new('ShaderNodeNewGeometry')
sep_p = nodes.new('ShaderNodeSeparateXYZ'); links.new(texco.outputs['Object'], sep_p.inputs[0])
sep_n = nodes.new('ShaderNodeSeparateXYZ'); links.new(geom.outputs['Normal'], sep_n.inputs[0])

def nop(op, a, b=None, v2=None):
    n = nodes.new('ShaderNodeMath'); n.operation = op
    for i, x in enumerate((a, b)):
        if x is None: continue
        if isinstance(x, (int, float)): n.inputs[i].default_value = x
        else: links.new(x, n.inputs[i])
    return n.outputs[0]

zmax, zmin = mx.z, mn.z
cx, cy = (mn.x + mx.x) / 2, (mn.y + mx.y) / 2
P = {'x': sep_p.outputs[0], 'y': sep_p.outputs[1], 'z': sep_p.outputs[2]}
Nn = {'x': sep_n.outputs[0], 'y': sep_n.outputs[1], 'z': sep_n.outputs[2]}

def projected_color(key):
    img, (w, h, l, r, t, b), mask = views[key]
    ppm = (b - t) / (zmax - zmin)
    if key in ('front', 'back'):
        axis, sign = 'x', (1 if key == 'front' else -1)
    else:
        # Facing image-right: the front (-Y) is on the right → u grows as y falls.
        axis, sign = 'y', (-1 if dirs[key] > 0 else 1)
    # Register on the torso band (hair/arms/feet sticking out don't skew the centre); profiles only paint
    # the head, so they register on the head band.
    f0, f1 = (0.58, 0.72) if key in ('front', 'back') else HEAD_BAND
    icx = band_center_img(mask, int(h), t, b, f0, f1)
    c0 = band_center_mesh(axis, f0, f1)
    if icx is None: icx = (l + r) / 2
    print('ALIGN', key, 'img centre', icx, 'mesh centre', c0)
    upx = nop('ADD', nop('MULTIPLY', nop('SUBTRACT', P[axis], c0), sign * ppm), icx)
    vpx = nop('ADD', nop('MULTIPLY', nop('SUBTRACT', zmax, P['z']), ppm), t)
    if key in head_map:
        hA, hB, hC, hD = head_map[key]
        hg = nodes.new('ShaderNodeMapRange'); hg.clamp = True
        hg.inputs['From Min'].default_value = zmin + (HEAD_Z0 - 0.03) * (zmax - zmin)
        hg.inputs['From Max'].default_value = zmin + HEAD_Z0 * (zmax - zmin)
        links.new(P['z'], hg.inputs['Value'])
        uh = nop('ADD', nop('MULTIPLY', P[axis], hB), hA)
        vh = nop('ADD', nop('MULTIPLY', P['z'], hD), hC)
        lerp = lambda a_, b_: nop('ADD', a_, nop('MULTIPLY', nop('SUBTRACT', b_, a_), hg.outputs[0]))
        upx = lerp(upx, uh); vpx = lerp(vpx, vh)
    u = nop('DIVIDE', upx, w)
    v = nop('SUBTRACT', 1.0, nop('DIVIDE', vpx, h))
    comb = nodes.new('ShaderNodeCombineXYZ')
    links.new(u, comb.inputs[0]); links.new(v, comb.inputs[1])
    tex = nodes.new('ShaderNodeTexImage'); tex.image = img; tex.extension = 'EXTEND'; tex.interpolation = 'Cubic'
    links.new(comb.outputs[0], tex.inputs[0])
    return tex.outputs['Color']

HEAD_BAND = (0.87, 0.96)
HEAD_Z0 = 0.845
vis_node = None
def vis_for_viewer(viewer):
    """viewer: 'front' (-Y), 'back' (+Y), 'mx' (-X), 'px' (+X) -> per-vertex visibility socket."""
    global vis_node
    if vis_node is None:
        va = nodes.new('ShaderNodeVertexColor'); va.layer_name = 'vis'
        sep = nodes.new('ShaderNodeSeparateColor'); links.new(va.outputs['Color'], sep.inputs[0])
        vis_node = (va, sep)
    va, sep = vis_node
    return {'front': sep.outputs[0], 'back': sep.outputs[1], 'mx': sep.outputs[2], 'px': va.outputs['Alpha']}[viewer]

def weight(key):
    # A profile facing image-right is seen from the character's right side (viewer at -X), and vice versa.
    if key in ('front', 'back'):
        comp, sign, viewer = 'y', (-1 if key == 'front' else 1), key
    else:
        comp, sign = 'x', (-1 if dirs[key] > 0 else 1)
        viewer = 'mx' if dirs[key] > 0 else 'px'
    side = key in ('left', 'right')
    base = nop('MAXIMUM', nop('MULTIPLY', Nn[comp], sign), 0.0)
    # Ignore grazing angles (stretch marks, silhouette line art), then sharpen.
    ramp = nodes.new('ShaderNodeMapRange'); ramp.clamp = True
    ramp.inputs['From Min'].default_value = 0.8 if side else 0.22
    ramp.inputs['From Max'].default_value = 0.95 if side else 0.85
    links.new(base, ramp.inputs['Value'])
    w = nop('POWER', ramp.outputs[0], 2.0)
    # Only paint what this view can actually see (no ghost limbs on the torso).
    w = nop('MULTIPLY', w, vis_for_viewer(viewer))
    if side:
        # Profiles only paint the head: below the neck, arms overlap the torso in a side view (ghost limbs).
        gate = nodes.new('ShaderNodeMapRange'); gate.clamp = True
        gate.inputs['From Min'].default_value = zmin + (HEAD_Z0 - 0.015) * (zmax - zmin)
        gate.inputs['From Max'].default_value = zmin + (HEAD_Z0 + 0.015) * (zmax - zmin)
        links.new(P['z'], gate.inputs['Value'])
        w = nop('MULTIPLY', w, gate.outputs[0])
    if not side:
        w = nop('ADD', w, nop('MULTIPLY', nop('ABSOLUTE', Nn['z']), 0.08))
    if key == 'front':
        # The face is line art drawn from the front: any surface on the front of the head (eye sockets, brow
        # ridges, cheeks) takes the front drawing, whatever its normal or occlusion.
        fg = nodes.new('ShaderNodeMapRange'); fg.clamp = True
        fg.inputs['From Min'].default_value = zmin + (HEAD_Z0 - 0.01) * (zmax - zmin)
        fg.inputs['From Max'].default_value = zmin + (HEAD_Z0 + 0.01) * (zmax - zmin)
        links.new(P['z'], fg.inputs['Value'])
        hemi = nodes.new('ShaderNodeMapRange'); hemi.clamp = True
        hemi.inputs['From Min'].default_value = -0.35; hemi.inputs['From Max'].default_value = -0.65   # the face, not the ears
        links.new(Nn['y'], hemi.inputs['Value'])
        w = nop('MAXIMUM', w, nop('MULTIPLY', nop('MULTIPLY', fg.outputs[0], hemi.outputs[0]), 3.0))
    return w

for k in ('front', 'back'):
    if k in views: register_vertical(k); register_head(k)
for k in ('left', 'right'):
    if k in views: register_head(k)   # profiles only paint the head: fit them to the mesh's head profile

# ---- vertex colours: sample front/back where confidently seen, flood-fill the rest across the mesh.
def t_of(view): return view[1][4]

def view_map(key):
    img, (w, h, l, r, t, b), mask = views[key]
    ppm = (b - t) / (zmax - zmin)
    icx = band_center_img(mask, int(h), t, b, 0.58, 0.72) or (l + r) / 2
    c0 = band_center_mesh('x', 0.58, 0.72)
    sign = 1 if key == 'front' else -1
    return img, w, h, ppm, icx, c0, sign
# Body vs arm per height slab: arms hang apart from the torso, so the central cluster of x positions is the torso.
_Hz0 = zmax - zmin
_NB = 64
_z0, _z1 = zmin + 0.40 * _Hz0, zmin + 0.84 * _Hz0
_slabs = [[] for _ in range(_NB)]
for v in obj.data.vertices:
    if _z0 <= v.co.z < _z1: _slabs[int((v.co.z - _z0) / (_z1 - _z0) * _NB)].append(v.co.x)
_torso = []
for xs_ in _slabs:
    if not xs_: _torso.append(None); continue
    xs_ = sorted(xs_)
    gap = 0.012 * _Hz0
    # walk out from the centre until a gap
    import bisect
    c_ = bisect.bisect_left(xs_, 0.0); c_ = min(max(c_, 0), len(xs_) - 1)
    lo = c_
    while lo > 0 and xs_[lo] - xs_[lo - 1] < gap: lo -= 1
    hi = c_
    while hi < len(xs_) - 1 and xs_[hi + 1] - xs_[hi] < gap: hi += 1
    _torso.append((xs_[lo], xs_[hi]))
def zone(i):
    co_ = obj.data.vertices[i].co
    if not (_z0 <= co_.z < _z1): return 0
    t_ = _torso[int((co_.z - _z0) / (_z1 - _z0) * _NB)]
    if t_ is None: return 0
    return 0 if t_[0] - 1e-4 <= co_.x <= t_[1] + 1e-4 else 1
zones = [zone(i) for i in range(len(obj.data.vertices))]
print('UNIQUE zones: arm verts', sum(zones))
# Code-kit sanity: the torso between hem and collar is shirt. Where a view would paint skin there (it is seeing
# the arm hanging in front, or the arm drawn slightly off), that view is not trusted for that vertex.
import colorsys
_Hz = zmax - zmin
_ch = [abs(v.co.x) for v in obj.data.vertices if zmin + 0.70 * _Hz <= v.co.z <= zmin + 0.74 * _Hz]
_thw0 = sorted(_ch)[int(len(_ch) * 0.6)] if _ch else 0.15 * _Hz
def kit_like(c):
    c = tuple(min(1.0, max(0.0, float(x))) for x in c)
    if max(c) - min(c) < 1e-6: return max(c) > 0.8 or max(c) < 0.22
    h_, s_, v_ = colorsys.rgb_to_hsv(*c)
    if v_ < 0.22: return True                       # ink / deep shading
    if s_ < 0.3: return v_ > 0.8                   # white trim/highlight, not grey-beige skin
    return h_ < 0.035 or h_ > 0.93 or abs(h_ - 0.14) < 0.05 or abs(h_ - 0.63) < 0.12 or abs(h_ - 0.37) < 0.12 or s_ > 0.62
_vis = obj.data.color_attributes['vis'].data
rejected = 0
for key, ch, ny in (('front', 0, -1), ('back', 1, 1)):
    if key not in views: continue
    img, w, h, ppm, icx, c0, sign = view_map(key)
    px = view_px[os.path.abspath(arg('--' + key))]
    H_, W_ = px.shape[0], px.shape[1]
    for v in obj.data.vertices:
        zf = (v.co.z - zmin) / _Hz
        if not (0.55 < zf < 0.76) or zones[v.index]: continue
        u = (v.co.x - c0) * sign * ppm + icx
        row_td = (zmax - v.co.z) * ppm + t_of(views[key])
        xi = int(max(0, min(W_ - 1, u))); yi = int(max(0, min(H_ - 1, H_ - 1 - row_td)))
        if not kit_like(tuple(float(x) for x in px[yi, xi, :3])):
            col_ = list(_vis[v.index].color); col_[ch] = 0.0; _vis[v.index].color = col_; rejected += 1
print('UNIQUE kit-check rejected', rejected, 'torso samples')
vcol = [None] * len(obj.data.vertices)
vconf = [0.0] * len(obj.data.vertices)
vis_data = obj.data.color_attributes['vis'].data
for key, ch, ny in (('front', 0, -1), ('back', 1, 1)):
    if key not in views: continue
    img, w, h, ppm, icx, c0, sign = view_map(key)
    px = view_px[os.path.abspath(arg('--' + key))]
    H_, W_ = px.shape[0], px.shape[1]
    for v in obj.data.vertices:
        facing = v.normal.y * ny
        vis = vis_data[v.index].color[ch]
        conf = max(0.0, min(1.0, (facing - 0.2) / 0.5)) * vis
        if key == 'front' and v.co.z > zmin + HEAD_Z0 * (zmax - zmin) and facing > 0.5:
            conf = max(conf, 0.9)
        if conf <= 0.05: continue
        u = (v.co.x - c0) * sign * ppm + icx
        row_td = (zmax - v.co.z) * ppm + t_of(views[key])
        if key in head_map:
            hA, hB, hC, hD = head_map[key]
            g = max(0.0, min(1.0, (v.co.z - (zmin + (HEAD_Z0 - 0.03) * (zmax - zmin))) / (0.03 * (zmax - zmin))))
            u += (hA + hB * v.co.x - u) * g
            row_td += (hC + hD * v.co.z - row_td) * g
        xi = int(max(0, min(W_ - 1, u))); yi = int(max(0, min(H_ - 1, H_ - 1 - row_td)))
        c = px[yi, xi, :3]
        if conf > vconf[v.index]:
            vconf[v.index] = conf; vcol[v.index] = (float(c[0]), float(c[1]), float(c[2]))
head_z0 = zmin + HEAD_Z0 * (zmax - zmin)
for key in [k for k in ('left', 'right') if k in views]:
    img, (w, h, l, r, t, b), mask = views[key]
    ppm = (b - t) / (zmax - zmin)
    sgn = -1 if dirs[key] > 0 else 1
    icx = band_center_img(mask, int(h), t, b, *HEAD_BAND) or (l + r) / 2
    c0 = band_center_mesh('y', *HEAD_BAND)
    nx = -1 if dirs[key] > 0 else 1
    ch = 2 if dirs[key] > 0 else 3
    px = view_px[os.path.abspath(arg('--' + key))]
    H_, W_ = px.shape[0], px.shape[1]
    for v in obj.data.vertices:
        if v.co.z < head_z0: continue
        facing = v.normal.x * nx
        vis = vis_data[v.index].color[ch]
        conf = max(0.0, min(1.0, (facing - 0.75) / 0.2)) * vis
        if conf <= 0.05: continue
        u = (v.co.y - c0) * sgn * ppm + icx
        row_td = (zmax - v.co.z) * ppm + t
        if key in head_map:
            hA, hB, hC, hD = head_map[key]
            u = hA + hB * v.co.y; row_td = hC + hD * v.co.z
        xi = int(max(0, min(W_ - 1, u))); yi = int(max(0, min(H_ - 1, H_ - 1 - row_td)))
        c = px[yi, xi, :3]
        if conf > vconf[v.index]:
            vconf[v.index] = conf; vcol[v.index] = (float(c[0]), float(c[1]), float(c[2]))
# Flood fill uncoloured vertices from coloured neighbours (breadth-first, averaging).
# Arms hang against the torso and the generator fuses them at the armpit: fill arm and body separately first,
# so skin never floods into the shirt (and shirt never onto the arm).
filled = 0
for strict in (True, False):
    while True:
        nxt = {}
        for i, c in enumerate(vcol):
            if c is not None: continue
            ns = [vcol[j] for j in adj[i] if vcol[j] is not None and (not strict or zones[j] == zones[i])]
            if ns: nxt[i] = tuple(sum(x[k] for x in ns) / len(ns) for k in range(3))
        if not nxt: break
        for i, c in nxt.items(): vcol[i] = c
        filled += len(nxt)
for i in range(len(vcol)):
    if vcol[i] is None: vcol[i] = (0.5, 0.5, 0.5)
# A couple of smoothing passes on the filled (low-confidence) vertices only.
for _ in range(3):
    nv = list(vcol)
    for i in range(len(vcol)):
        if vconf[i] < 0.3 and adj[i]:
            ns = [vcol[j] for j in adj[i] if zones[j] == zones[i]] + [vcol[i]]
            nv[i] = tuple(sum(x[k] for x in ns) / len(ns) for k in range(3))
    vcol = nv
vc_layer = obj.data.color_attributes.new(name='vcol', type='FLOAT_COLOR', domain='POINT')
def _lin(x): return x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4
# Image pixels are sRGB-encoded; colour attributes are linear (otherwise the fill bakes out washed-out).
for i, c in enumerate(vcol): vc_layer.data[i].color = (_lin(c[0]), _lin(c[1]), _lin(c[2]), vconf[i])
print('UNIQUE vertex colours: filled', filled, 'of', len(vcol))

cols, ws = [], []
for k in [k for k in views if k in ('front', 'back', 'left', 'right') and k not in os.environ.get('DEBUG_SKIP', '').split(',')]:
    cols.append(projected_color(k)); ws.append(weight(k))
wsum = ws[0]
for w in ws[1:]: wsum = nop('ADD', wsum, w)
acc = None
for c, w in zip(cols, ws):
    f = nop('DIVIDE', w, wsum)
    mix = nodes.new('ShaderNodeVectorMath'); mix.operation = 'SCALE'
    links.new(c, mix.inputs[0]); links.new(f, mix.inputs['Scale'])
    if acc is None: acc = mix.outputs[0]
    else:
        add = nodes.new('ShaderNodeVectorMath'); add.operation = 'ADD'
        links.new(acc, add.inputs[0]); links.new(mix.outputs[0], add.inputs[1]); acc = add.outputs[0]
vc = nodes.new('ShaderNodeVertexColor'); vc.layer_name = 'vcol'
conf = nop('MINIMUM', nop('MULTIPLY', wsum, 1.6), 1.0)
mixn = nodes.new('ShaderNodeMix'); mixn.data_type = 'RGBA'
links.new(conf, mixn.inputs['Factor']) if not os.environ.get('DEBUG_VCOL') else setattr(mixn.inputs['Factor'], 'default_value', 0.0)
links.new(vc.outputs['Color'], mixn.inputs['A'])
links.new(acc, mixn.inputs['B'])
links.new(mixn.outputs['Result'], emit.inputs['Color'])
bake_img = bpy.data.images.new('bake', TEX, TEX, alpha=False)
bake_node = nodes.new('ShaderNodeTexImage'); bake_node.image = bake_img
nodes.active = bake_node
obj.data.materials.append(mat)

scene.render.engine = 'CYCLES'
scene.cycles.samples = 1
scene.cycles.device = 'CPU'
bpy.context.view_layer.objects.active = obj; obj.select_set(True)
scene.render.bake.margin = 8
bpy.ops.object.bake(type='EMIT')
tex_path = os.path.join(ROOT, 'Panna', 'Resources', 'Characters', NAME + '.png')
bake_img.filepath_raw = tex_path
bake_img.file_format = 'PNG'
bake_img.save()
bake_img.pack()
# Ship as JPEG (10x smaller than PNG, no visible loss for painted art).
import subprocess
jpg = tex_path[:-4] + '.jpg'
subprocess.run(['sips', '-s', 'format', 'jpeg', '-s', 'formatOptions', '88', tex_path, '--out', jpg], capture_output=True)
if os.path.exists(jpg) and '/Panna/Resources/' in tex_path: os.remove(tex_path)
print('UNIQUE baked texture', jpg)

# ------------------------------------------------------------------ cloth map (same projection, cloth masks instead of colours)
import colorsys as _cs
for k in list(views.keys()):
    img_k = views[k][0]
    hh, ww = int(views[k][1][1]), int(views[k][1][0])
    cm = view_cloth.get(os.path.abspath(arg('--' + k))) if k in ('front', 'back') else None
    if cm is None or cm.shape != (hh, ww): cm = np.zeros((hh, ww), np.float32)
    img_k.pixels[:] = np.dstack([cm, cm, cm, np.ones_like(cm)]).ravel()
    img_k.update()
def _cloth_v(c):
    c = tuple(min(1.0, max(0.0, float(x))) for x in c)
    if max(c) < 1e-4 or max(c) - min(c) < 1e-6: return 0.0
    h_, s_, v_ = _cs.rgb_to_hsv(*c)
    if s_ < 0.35 or v_ < 0.12: return 0.0
    return 1.0 if (h_ < 0.035 or h_ > 0.93 or abs(h_ - 0.14) < 0.05 or abs(h_ - 0.63) < 0.12 or abs(h_ - 0.37) < 0.12) else 0.0
for i, c in enumerate(vcol):
    cv = _cloth_v(c)
    vc_layer.data[i].color = (cv, cv, cv, vconf[i])
cloth_img = bpy.data.images.new('cloth', 1024, 1024, alpha=False)
bake_node.image = cloth_img
nodes.active = bake_node
bpy.ops.object.bake(type='EMIT')
print('UNIQUE cloth map baked')

if os.environ.get('DEBUG_FLANK'):
    bpx = np.array(bake_img.pixels[:], dtype=np.float32).reshape(TEX, TEX, 4)
    uvd = obj.data.uv_layers.active.data
    vuv = {}
    for poly in obj.data.polygons:
        for li in poly.loop_indices:
            vuv[obj.data.loops[li].vertex_index] = uvd[li].uv
    vis_ = obj.data.color_attributes['vis'].data; vc_ = obj.data.color_attributes['vcol'].data
    cand = [v for v in obj.data.vertices if abs(v.co.z - (zmin + 0.66 * (zmax - zmin))) < 0.02 and v.normal.x > 0.3]
    cand.sort(key=lambda v: v.co.y)
    for v in cand[::max(1, len(cand) // 14)]:
        uv = vuv.get(v.index)
        t_ = bpx[int(uv[1] * (TEX - 1)), int(uv[0] * (TEX - 1)), :3] if uv else None
        print('FLANK x%.3f y%.3f n(%.2f,%.2f) vis(%.2f,%.2f) vcol(%.2f,%.2f,%.2f) tex(%.2f,%.2f,%.2f) zone%d' % (v.co.x, v.co.y, v.normal.x, v.normal.y, vis_[v.index].color[0], vis_[v.index].color[1], *vc_[v.index].color[:3], *t_, zones[v.index]))
# ------------------------------------------------------------------ rig (landmarks from mesh analysis)
H = mx.z - mn.z
vs = [v.co.copy() for v in obj.data.vertices]
def slab(z0, z1):
    return [v for v in vs if z0 <= v.z <= z1]
def depth_at(x, z, r=0.06):
    near = [v.y for v in vs if abs(v.z - z) < r and abs(v.x - x) < r]
    return sum(near) / len(near) if near else 0.0
# Torso half-width at chest height; arms are what lies beyond it.
chest_slab = slab(mn.z + 0.70 * H, mn.z + 0.74 * H)
torso_hw = sorted(abs(v.x) for v in chest_slab)[int(len(chest_slab) * 0.6)] if chest_slab else 0.15 * H
arm_pts = {1: [], -1: []}
for v in slab(mn.z + 0.40 * H, mn.z + 0.80 * H):
    if abs(v.x) > torso_hw * 1.05: arm_pts[1 if v.x > 0 else -1].append(v)
def J(x, z): return Vector((x, depth_at(x, z), z))
Zf = lambda f: mn.z + f * H
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
for s, side in ((1, 'L'), (-1, 'R')):
    pts = arm_pts[s]
    sh = J(s * torso_hw * 0.95, Zf(0.785))
    if pts:
        hand = min(pts, key=lambda v: v.z)                # lowest arm point = fingertips
        tip = Vector((hand.x, depth_at(hand.x, hand.z), hand.z))
    else:
        tip = J(s * 0.3 * H, Zf(0.45))
    d = tip - sh
    wrist = sh + d * 0.84
    elbow = sh + d * 0.47 + Vector((0, 0.01, 0))
    bone('upperarm.' + side, sh, elbow, 'chest')
    bone('forearm.' + side, elbow, wrist, 'upperarm.' + side)
    bone('hand.' + side, wrist, tip, 'forearm.' + side)
    hip = J(s * 0.055 * H, Zf(0.49))
    knee = J(s * 0.058 * H, Zf(0.27))
    ankle = J(s * 0.06 * H, Zf(0.055))
    bone('thigh.' + side, hip, knee, 'hips')
    bone('shin.' + side, knee, ankle, 'thigh.' + side)
    toe = Vector((ankle.x, mn.y + 0.03, Zf(0.015)))
    bone('foot.' + side, ankle, toe, 'shin.' + side)
bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.object.select_all(action='DESELECT'); obj.select_set(True); ro.select_set(True); bpy.context.view_layer.objects.active = ro
bpy.ops.object.parent_set(type='ARMATURE_AUTO')
# Smooth skin weights so cloth (shorts, sleeves) bends softly instead of ballooning at the joints.
bpy.ops.object.select_all(action='DESELECT'); obj.select_set(True); bpy.context.view_layer.objects.active = obj
bpy.ops.object.mode_set(mode='WEIGHT_PAINT')
bpy.ops.object.vertex_group_smooth(group_select_mode='ALL', factor=0.6, repeat=6, expand=0.0)
bpy.ops.object.vertex_group_normalize_all(group_select_mode='ALL', lock_active=False)
bpy.ops.object.mode_set(mode='OBJECT')
# Pelvis/shorts: blend thighs toward hips so leg swings don't drag the shorts outward.
hg = obj.vertex_groups.get('hips')
if hg:
    for v in obj.data.vertices:
        z = v.co.z
        if mn.z + 0.42 * H < z < mn.z + 0.56 * H:
            for g in v.groups:
                name = obj.vertex_groups[g.group].name
                if name.startswith('thigh.') and abs(v.co.x) < 0.09 * H:
                    t = (z - (mn.z + 0.42 * H)) / (0.14 * H)
                    moved = g.weight * min(0.8, t)
                    g.weight -= moved
                    hg.add([v.index], moved, 'ADD')
    bpy.ops.object.select_all(action='DESELECT'); obj.select_set(True); bpy.context.view_layer.objects.active = obj
    bpy.ops.object.vertex_group_normalize_all(group_select_mode='ALL', lock_active=False)
unweighted = sum(1 for v in obj.data.vertices if sum(g.weight for g in v.groups) < 0.01)
print('UNIQUE rig unweighted verts', unweighted, 'of', len(obj.data.vertices))
# Anything left unweighted snaps to the nearest bone head.
if unweighted:
    heads = [(b.name, b.head_local) for b in arm.bones]
    for v in obj.data.vertices:
        if sum(g.weight for g in v.groups) < 0.01:
            nm = min(heads, key=lambda h: (h[1] - v.co).length)[0]
            obj.vertex_groups[nm].add([v.index], 1.0, 'REPLACE')

# ------------------------------------------------------------------ kit region mask (clothing zone from the skeleton)
kit_bones = {'hips', 'spine', 'chest', 'thigh.L', 'thigh.R', 'shin.L', 'shin.R', 'upperarm.L', 'upperarm.R'}
gname = {g.index: g.name for g in obj.vertex_groups}
km = obj.data.color_attributes.new(name='kitmask', type='FLOAT_COLOR', domain='POINT')
neck_z = mn.z + 0.86 * H
for v in obj.data.vertices:
    tot = sum(g.weight for g in v.groups) or 1
    hw = sum(g.weight for g in v.groups if gname.get(g.group) in ('head', 'neck')) / tot
    aw = sum(g.weight for g in v.groups if gname.get(g.group, '').startswith(('forearm', 'hand'))) / tot
    val = 1.0 - min(1.0, max(0.0, (hw - 0.35) / 0.3))
    # Below the collarbone it is always shirt (the neck bone's weights reach the upper chest).
    zf = (v.co.z - mn.z) / H
    # (except big-headed characters whose chin sits low: strong head/neck weight still wins)
    hhead = sum(g.weight for g in v.groups if gname.get(g.group) == 'head') / tot
    headish = min(1.0, max(0.0, (hhead - 0.5) / 0.3))   # the head bone only: neck weights bleed onto the chest
    if zf < 0.79: val = max(val, 1.0 - headish)
    elif zf < 0.81: val = max(val, (0.81 - zf) / 0.02 * (1.0 - headish))
    if v.co.z > neck_z: val = 0.0
    elif v.co.z > neck_z - 0.02 * H: val *= (neck_z - v.co.z) / (0.02 * H)
    km.data[v.index].color = (val, val, val, 1)
mm = bpy.data.materials.new('maskbake'); mm.use_nodes = True
mt = mm.node_tree; mt.nodes.clear()
mo = mt.nodes.new('ShaderNodeOutputMaterial'); me_ = mt.nodes.new('ShaderNodeEmission'); vcn = mt.nodes.new('ShaderNodeVertexColor'); vcn.layer_name = 'kitmask'
# Region = clothing zone (skeleton) x cloth map (what the drawing says is kit, not skin/hair).
ctex = mt.nodes.new('ShaderNodeTexImage'); ctex.image = cloth_img; ctex.interpolation = 'Linear'
cmul = mt.nodes.new('ShaderNodeMix'); cmul.data_type = 'RGBA'; cmul.blend_type = 'MULTIPLY'; cmul.inputs['Factor'].default_value = 1.0
mt.links.new(vcn.outputs['Color'], cmul.inputs['A']); mt.links.new(ctex.outputs['Color'], cmul.inputs['B'])
mt.links.new(cmul.outputs['Result'], me_.inputs['Color']); mt.links.new(me_.outputs[0], mo.inputs['Surface'])
mimg = bpy.data.images.new('maskimg', 1024, 1024, alpha=False)
mnode = mt.nodes.new('ShaderNodeTexImage'); mnode.image = mimg; mt.nodes.active = mnode
saved_mats = list(obj.data.materials)
obj.data.materials.clear(); obj.data.materials.append(mm)
bpy.ops.object.select_all(action='DESELECT'); obj.select_set(True); bpy.context.view_layer.objects.active = obj
scene.render.bake.margin = 6
bpy.ops.object.bake(type='EMIT')
mask_path = os.path.join(ROOT, 'Panna', 'Resources', 'Characters', NAME + '_mask.png')
mimg.filepath_raw = mask_path; mimg.file_format = 'PNG'; mimg.save()
import subprocess
subprocess.run(['sips', '-s', 'format', 'png', '-m', '/System/Library/ColorSync/Profiles/Generic Gray Profile.icc', mask_path], capture_output=True)
obj.data.materials.clear()
for m_ in saved_mats: obj.data.materials.append(m_)
print('UNIQUE kit mask', mask_path)

# ------------------------------------------------------------------ export (same binary format as base.bin)
C = Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, -1, 0, 0), (0, 0, 0, 1)))
def to_scn(v): return [round(v[0], 5), round(v[2], 5), round(-v[1], 5)]
bones = []
names = [b.name for b in arm.bones]
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
        n = cn[li].vector if cn is not None else me.vertices[vi].normal
        uv = tuple(uvl.data[li].uv)
        key = (vi, round(uv[0], 5), round(uv[1], 5))
        if key not in index_of:
            index_of[key] = len(positions)
            positions.append(to_scn(me.vertices[vi].co)); normals.append(to_scn(n.normalized()))
            uvs.append([round(uv[0], 5), round(1 - uv[1], 5)])
            ws = sorted(((g.weight, names.index(groups[g.group])) for g in me.vertices[vi].groups if groups.get(g.group) in names and g.weight > 0.001), reverse=True)[:4]
            tot = sum(w for w, _ in ws) or 1
            ws = [(w / tot, b) for w, b in ws] + [(0, 0)] * (4 - len(ws))
            joints.append([b for _, b in ws]); weights.append([round(w, 4) for w, _ in ws])
        tris.append(index_of[key])
blob = bytearray()
def put(fmt, arr):
    off = len(blob); blob.extend(struct.pack('<%d%s' % (len(arr), fmt), *arr))
    while len(blob) % 4: blob.append(0)
    return off
flat = lambda a: [c for x in a for c in x]
n = len(positions)
idx_fmt = 'H' if n < 65535 else 'I'
meta = [{'name': NAME, 'slot': 'unique', 'count': n, 'pos': put('f', flat(positions)), 'nor': put('f', flat(normals)), 'uv': put('f', flat(uvs)),
         'joints': put('H', flat(joints)), 'weights': put('f', flat(weights)),
         'groups': [{'material': 'unique', 'offset': put(idx_fmt, tris), 'count': len(tris)}], 'index32': idx_fmt == 'I'}]
head_c = [0, mn.z + 0.905 * H, 0]
header = json.dumps({'version': 2, 'bones': bones, 'meshes': meta, 'headCenter': to_scn(head_c), 'headRadius': 0.09 * H}, separators=(',', ':')).encode()
while (4 + len(header)) % 4: header += b' '
dest = os.path.join(ROOT, 'Panna', 'Resources', 'Characters', NAME + '.bin')
with open(dest, 'wb') as f:
    f.write(struct.pack('<I', len(header))); f.write(header); f.write(blob)
print('UNIQUE exported', dest, os.path.getsize(dest), 'bytes', n, 'verts', len(tris) // 3, 'tris')

# ------------------------------------------------------------------ preview
if '--preview' in A:
    for o in (obj,):
        o.data.materials.clear()
        pm = bpy.data.materials.new('prev'); pm.use_nodes = True
        t = pm.node_tree; t.nodes.clear()
        o2 = t.nodes.new('ShaderNodeOutputMaterial'); e = t.nodes.new('ShaderNodeEmission'); ti = t.nodes.new('ShaderNodeTexImage')
        ti.image = bake_img; t.links.new(ti.outputs[0], e.inputs[0]); t.links.new(e.outputs[0], o2.inputs[0])
        o.data.materials.append(pm)
    ro.hide_render = True
    scene.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items] else 'BLENDER_EEVEE'
    scene.render.resolution_x, scene.render.resolution_y = 700, 1000
    w = bpy.data.worlds.new('w'); scene.world = w; w.color = (0.9, 0.9, 0.92)
    cd = bpy.data.cameras.new('c'); cd.type = 'ORTHO'; cd.ortho_scale = H * 1.15
    cam = bpy.data.objects.new('c', cd); scene.collection.objects.link(cam); scene.camera = cam
    for nm, deg in (('front', 0), ('34', 40), ('side', 90), ('back', 180)):
        a = math.radians(deg)
        cam.location = (math.sin(a) * 6, -math.cos(a) * 6, mn.z + H * 0.52)
        cam.rotation_euler = (math.radians(90), 0, a)
        scene.render.filepath = os.path.join(ROOT, 'art', 'ai3d', f'{NAME}_proj_{nm}.png')
        bpy.ops.render.render(write_still=True)
    # Head close-ups at full texture resolution (what the locker / pack reveal camera sees).
    cd.ortho_scale = H * 0.2
    scene.render.resolution_x, scene.render.resolution_y = 600, 600
    for nm, deg in (('front', 0), ('34', 40), ('side', 90)):
        a = math.radians(deg)
        cam.location = (math.sin(a) * 6, -math.cos(a) * 6, mn.z + H * 0.91)
        cam.rotation_euler = (math.radians(90), 0, a)
        scene.render.filepath = os.path.join(ROOT, 'art', 'ai3d', f'{NAME}_head_{nm}.png')
        bpy.ops.render.render(write_still=True)
