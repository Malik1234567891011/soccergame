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
bpy.ops.import_scene.gltf(filepath=os.path.abspath(arg('--mesh')))
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
for sgn, side in ((1, 'L'), (-1, 'R')):
    pts = armband[(armband[:, 0] * sgn) > torso_hw * 1.05]
    sh = J(sgn * torso_hw * 0.95, Zf(0.785))
    if len(pts):
        hand = pts[np.argmin(pts[:, 2])]
        tip = Vector((hand[0], depth_at(hand[0], hand[2]), hand[2]))
    else:
        tip = J(sgn * 0.3 * H, Zf(0.45))
    d = tip - sh
    bone('upperarm.' + side, sh, sh + d * 0.47 + Vector((0, 0.01, 0)), 'chest')
    bone('forearm.' + side, sh + d * 0.47 + Vector((0, 0.01, 0)), sh + d * 0.84, 'upperarm.' + side)
    bone('hand.' + side, sh + d * 0.84, tip, 'forearm.' + side)
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
proxy = obj.copy(); proxy.data = obj.data.copy(); scene.collection.objects.link(proxy)
rm = proxy.modifiers.new('vox', 'REMESH'); rm.mode = 'VOXEL'; rm.voxel_size = 0.009 * H; rm.use_smooth_shade = True
bpy.ops.object.select_all(action='DESELECT'); proxy.select_set(True); bpy.context.view_layer.objects.active = proxy
bpy.ops.object.modifier_apply(modifier='vox')
proxy.data.materials.clear()
bpy.ops.object.select_all(action='DESELECT'); proxy.select_set(True); ro.select_set(True); bpy.context.view_layer.objects.active = ro
bpy.ops.object.parent_set(type='ARMATURE_AUTO')
print('TRIPO proxy', len(proxy.data.vertices), 'verts; weighted', sum(1 for v in proxy.data.vertices if v.groups))
for b in arm.bones: obj.vertex_groups.new(name=b.name)
dt = obj.modifiers.new('dt', 'DATA_TRANSFER'); dt.object = proxy
dt.use_vert_data = True; dt.data_types_verts = {'VGROUP_WEIGHTS'}; dt.vert_mapping = 'POLYINTERP_NEAREST'
dt.layers_vgroup_select_src = 'ALL'; dt.layers_vgroup_select_dst = 'NAME'
bpy.ops.object.select_all(action='DESELECT'); obj.select_set(True); bpy.context.view_layer.objects.active = obj
bpy.ops.object.modifier_apply(modifier='dt')
bpy.data.objects.remove(proxy)
obj.parent = ro
am = obj.modifiers.new('Armature', 'ARMATURE'); am.object = ro
bpy.ops.object.select_all(action='DESELECT'); obj.select_set(True); bpy.context.view_layer.objects.active = obj
bpy.ops.object.mode_set(mode='WEIGHT_PAINT')
bpy.ops.object.vertex_group_smooth(group_select_mode='ALL', factor=0.5, repeat=4, expand=0.0)
bpy.ops.object.vertex_group_normalize_all(group_select_mode='ALL', lock_active=False)
bpy.ops.object.mode_set(mode='OBJECT')
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
R = 0.075 * H
for v in obj.data.vertices:
    for g in list(v.groups):
        if g.group in arm_idx and g.weight > 0:
            d = min(seg_d(v.co, a, b) for a, b in chains[arm_idx[g.group][-1]])
            if d > R:
                f = min(1.0, (d - R) / (0.5 * R)); moved = g.weight * f; g.weight -= moved
                (hg if v.co.z < Zf(0.6) else obj.vertex_groups['chest']).add([v.index], moved, 'ADD')
bpy.ops.object.vertex_group_normalize_all(group_select_mode='ALL', lock_active=False)
heads = [(b.name, b.head_local) for b in arm.bones]
for v in obj.data.vertices:
    if sum(g.weight for g in v.groups) < 0.01:
        obj.vertex_groups[min(heads, key=lambda h: (h[1] - v.co).length)[0]].add([v.index], 1.0, 'REPLACE')

# ------------------------------------------------------------------ kit region mask = clothing zone (skeleton) × cloth colour (texture)
gname = {g.index: g.name for g in obj.vertex_groups}
km = obj.data.color_attributes.new(name='kitmask', type='FLOAT_COLOR', domain='POINT')
for v in obj.data.vertices:
    tot = sum(g.weight for g in v.groups) or 1
    hh = sum(g.weight for g in v.groups if gname.get(g.group) == 'head') / tot
    val = 1.0 - min(1.0, max(0.0, (hh - 0.15) / 0.25))
    if v.co.z > Zf(0.86): val = 0.0
    km.data[v.index].color = (val, val, val, 1)
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
zone = np.array(zimg.pixels[:], dtype=np.float32).reshape(T, T, 4)[:, :, 0]
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
cloth = dil(ero(cloth, 1), 2) & (zone > 0.3)
mask = (cloth.astype(np.float32) * np.clip(zone, 0, 1))
mimg = bpy.data.images.new('mask', T, T, alpha=False)
mimg.pixels[:] = np.dstack([mask, mask, mask, np.ones_like(mask)]).ravel()
mask_path = os.path.join(OUT, NAME + '_mask.png')
mimg.filepath_raw = mask_path; mimg.file_format = 'PNG'; mimg.save()
subprocess.run(['sips', '-Z', '1024', '-s', 'format', 'png', '-m', '/System/Library/ColorSync/Profiles/Generic Gray Profile.icc', mask_path], capture_output=True)
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
    cd.ortho_scale = H * 0.2
    scene.render.resolution_x, scene.render.resolution_y = 600, 600
    for nm, deg in (('front', 0), ('34', 40)):
        a = math.radians(deg)
        cam.location = (math.sin(a) * 6, -math.cos(a) * 6, mn.z + H * 0.91)
        cam.rotation_euler = (math.radians(90), 0, a)
        scene.render.filepath = os.path.join(ROOT, 'art', 'tripo', f'{NAME}_head_{nm}.png')
        bpy.ops.render.render(write_still=True)
