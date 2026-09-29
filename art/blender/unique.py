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

# ------------------------------------------------------------------ UVs
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004)
bpy.ops.object.mode_set(mode='OBJECT')

# ------------------------------------------------------------------ views
def load_view(path):
    img = bpy.data.images.load(os.path.abspath(path))
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)  # bottom-up rows
    bg = np.median(np.concatenate([px[:8, :8, :3].reshape(-1, 3), px[-8:, -8:, :3].reshape(-1, 3), px[:8, -8:, :3].reshape(-1, 3)]), axis=0)
    diff = np.abs(px[:, :, :3] - bg).sum(axis=2)
    mask = diff > 0.12
    ys, xs = np.nonzero(mask)
    # Erode: anti-aliased silhouette pixels are half background — drop them so they get refilled by dilation.
    er = mask.copy()
    for _ in range(3):
        er &= np.roll(er, 1, 0) & np.roll(er, -1, 0) & np.roll(er, 1, 1) & np.roll(er, -1, 1)
    fill_mask = er
    # rows are bottom-up: convert to top-down pixel coords
    top = h - 1 - ys.max(); bottom = h - 1 - ys.min()
    left = xs.min(); right = xs.max()
    # Dilate figure colours outward so silhouette sampling never picks up background.
    col = px.copy()
    m = fill_mask.copy()
    for _ in range(40):
        grown = m.copy()
        acc = np.zeros_like(col[:, :, :3]); cnt = np.zeros(m.shape, dtype=np.float32)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            sm = np.roll(m, (dy, dx), axis=(0, 1))
            sc = np.roll(col[:, :, :3], (dy, dx), axis=(0, 1))
            add = sm & ~m
            acc[add] += sc[add]; cnt[add] += 1
            grown |= sm
        newp = grown & ~m
        col[newp, :3] = acc[newp] / np.maximum(cnt[newp], 1)[:, None]
        m = grown
    img.pixels[:] = col.ravel()
    img.update()
    print('VIEW', os.path.basename(path), 'figure px x', left, right, 'y', top, bottom)
    return img, (float(w), float(h), float(left), float(right), float(top), float(bottom)), mask

views = {}
for k in ('front', 'back', 'left', 'right'):
    p = arg('--' + k)
    if p: views[k] = load_view(p)

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
if len(side_keys) == 2 and dirs['left'] == dirs['right']:
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
    # Register on the torso band (hair/arms/feet sticking out don't skew the centre).
    icx = band_center_img(mask, int(h), t, b, 0.58, 0.72)
    c0 = band_center_mesh(axis, 0.58, 0.72)
    if icx is None: icx = (l + r) / 2
    print('ALIGN', key, 'img centre', icx, 'mesh centre', c0)
    upx = nop('ADD', nop('MULTIPLY', nop('SUBTRACT', P[axis], c0), sign * ppm), icx)
    vpx = nop('ADD', nop('MULTIPLY', nop('SUBTRACT', zmax, P['z']), ppm), t)
    u = nop('DIVIDE', upx, w)
    v = nop('SUBTRACT', 1.0, nop('DIVIDE', vpx, h))
    comb = nodes.new('ShaderNodeCombineXYZ')
    links.new(u, comb.inputs[0]); links.new(v, comb.inputs[1])
    tex = nodes.new('ShaderNodeTexImage'); tex.image = img; tex.extension = 'EXTEND'; tex.interpolation = 'Cubic'
    links.new(comb.outputs[0], tex.inputs[0])
    return tex.outputs['Color']

def weight(key):
    # A profile facing image-right is seen from the character's right side (viewer at -X), and vice versa.
    if key in ('front', 'back'):
        comp, sign = 'y', (-1 if key == 'front' else 1)
    else:
        comp, sign = 'x', (-1 if dirs[key] > 0 else 1)
    base = nop('MAXIMUM', nop('MULTIPLY', Nn[comp], sign), 0.0)
    w = nop('POWER', base, 4.0)
    # Fronts/backs also cover upward/downward-facing surfaces a little.
    if key in ('front', 'back'):
        w = nop('ADD', w, nop('MULTIPLY', nop('ABSOLUTE', Nn['z']), 0.08))
    return nop('ADD', w, 0.0005)

cols, ws = [], []
for k in views:
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
links.new(acc, emit.inputs['Color'])
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
print('UNIQUE baked texture', tex_path)

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
unweighted = sum(1 for v in obj.data.vertices if sum(g.weight for g in v.groups) < 0.01)
print('UNIQUE rig unweighted verts', unweighted, 'of', len(obj.data.vertices))
# Anything left unweighted snaps to the nearest bone head.
if unweighted:
    heads = [(b.name, b.head_local) for b in arm.bones]
    for v in obj.data.vertices:
        if sum(g.weight for g in v.groups) < 0.01:
            nm = min(heads, key=lambda h: (h[1] - v.co).length)[0]
            obj.vertex_groups[nm].add([v.index], 1.0, 'REPLACE')

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
