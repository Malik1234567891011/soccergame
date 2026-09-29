"""
PANNA character base-mesh builder. Run headless:
  /Applications/Blender.app/Contents/MacOS/Blender -b -P art/blender/character.py -- [--preview] [--export]

Builds a stylised anime footballer (layered clothing meshes over an organic skin-modifier body),
rigs it with an armature using automatic weights, and exports a compact JSON skinned-mesh file that
the iOS app loads directly into SceneKit (SCNSkinner). Hairstyles are exported as separate rigid meshes.

Blender space: Z up, character faces -Y. Export converts to SceneKit: (x, z, -y), facing +Z.
"""
import bpy, bmesh, math, json, sys, os
from mathutils import Vector, Matrix

ARGS = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
OUT = os.path.join(ROOT, 'art', 'build')
os.makedirs(OUT, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

# ---------------------------------------------------------------- proportions
HEAD_C = Vector((0, 0.0, 1.73))
HEAD_R = 0.235
SH = Vector((0.2, 0, 1.39))     # shoulder joint (left, +x)
EL = Vector((0.33, 0.01, 1.165))   # elbow
WR = Vector((0.43, 0.0, 0.965))     # wrist
HP = Vector((0.095, 0, 0.9))       # hip joint
KN = Vector((0.108, -0.005, 0.5))  # knee
AN = Vector((0.118, 0.01, 0.115))  # ankle

MATS = {}
def mat(name, rgb):
    if name in MATS: return MATS[name]
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb, 1)
    MATS[name] = m
    return m

SKIN = mat('skin', (0.93, 0.72, 0.58))
SHIRT = mat('shirt', (0.55, 0.95, 0.2))
TRIM = mat('trim', (0.9, 0.15, 0.45))
SHORTS = mat('shorts', (0.08, 0.08, 0.1))
SOCKS = mat('socks', (0.08, 0.08, 0.1))
BAND = mat('sockband', (0.55, 0.95, 0.2))
BOOT = mat('boot', (0.1, 0.1, 0.12))
SOLE = mat('sole', (0.55, 0.95, 0.2))
ACCENT = mat('bootaccent', (0.9, 0.15, 0.45))
HAIR = mat('hair', (0.85, 0.12, 0.45))
HEADM = mat('head', (0.93, 0.72, 0.58))
EAR = mat('skin', (0.93, 0.72, 0.58))

def link(obj):
    scene.collection.objects.link(obj)
    return obj

def skin_mesh(name, verts, edges, radii, material, subdiv=2, root=0):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], edges, [])
    obj = link(bpy.data.objects.new(name, me))
    mod = obj.modifiers.new('skin', 'SKIN')
    mod.use_smooth_shade = True
    mod.branch_smoothing = 0.6
    sv = me.skin_vertices[0].data
    for i, r in enumerate(radii):
        if isinstance(r, (int, float)): r = (r, r)
        sv[i].radius = r
    sv[root].use_root = True
    sub = obj.modifiers.new('sub', 'SUBSURF')
    sub.levels = subdiv
    sub.render_levels = subdiv
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier='skin')
    bpy.ops.object.modifier_apply(modifier='sub')
    obj.select_set(False)
    obj.data.materials.append(material)
    for p in obj.data.polygons: p.use_smooth = True
    return obj

def mirror_x(v): return Vector((-v.x, v.y, v.z))

# ---------------------------------------------------------------- body (visible skin: neck, arms, legs)
def build_body():
    V, E, R = [], [], []
    def add(p, r, parent=None):
        V.append(Vector(p)); R.append(r)
        i = len(V) - 1
        if parent is not None: E.append((parent, i))
        return i
    # spine core (hidden under clothes, keeps limbs connected for good weights)
    pel = add((0, 0, 0.95), (0.13, 0.1))
    ch = add((0, 0, 1.25), (0.15, 0.1), pel)
    nb = add((0, 0.005, 1.43), 0.07, ch)
    add((0, 0.01, 1.57), 0.064, nb)
    for s in (1, -1):
        f = (lambda v: v) if s == 1 else mirror_x
        sh = add(f(SH), 0.08, ch)
        el = add(f(EL), 0.064, sh)
        add(f(WR), 0.052, el)
        hp = add(f(HP), 0.112, pel)
        mid = add(f((HP + KN) / 2), 0.1, hp)
        kn = add(f(KN), 0.078, mid)
        calf = add(f(Vector((KN.x + 0.004, KN.y + 0.018, 0.32))), (0.088, 0.094), kn)
        add(f(AN), 0.058, calf)
    body = skin_mesh('body', V, E, R, SKIN)
    body.data.materials.append(SOCKS)
    body.data.materials.append(BAND)
    body.data.materials.append(SHORTS)
    body.data.materials.append(SHIRT)
    body.data.materials.append(mat('skin_arm', (0.93, 0.72, 0.58)))
    for p in body.data.polygons:
        c = p.center
        z = c.z
        if z < 0.43: p.material_index = 1
        elif z < 0.47: p.material_index = 2
        elif abs(c.x) < 0.2 and 0.84 < z < 1.02: p.material_index = 3
        elif abs(c.x) < 0.2 and 1.02 <= z < 1.42: p.material_index = 4
        elif abs(c.x) >= 0.17 and z > 0.9: p.material_index = 5
    return body

# ---------------------------------------------------------------- shirt
def build_shirt():
    V, E, R = [], [], []
    def add(p, r, parent=None):
        V.append(Vector(p)); R.append(r)
        i = len(V) - 1
        if parent is not None: E.append((parent, i))
        return i
    hem = add((0, 0.004, 0.9), (0.2, 0.148))
    waist = add((0, 0, 1.06), (0.185, 0.135), hem)
    chest = add((0, -0.006, 1.25), (0.215, 0.145), waist)
    top = add((0, 0.004, 1.39), (0.19, 0.12), chest)
    add((0, 0.008, 1.455), (0.08, 0.076), top)
    for s in (1, -1):
        f = (lambda v: v) if s == 1 else mirror_x
        a = add(f(Vector((0.18, 0.004, 1.39))), 0.108, top)
        add(f(SH + (EL - SH) * 0.5 + Vector((0, 0, 0.005))), (0.097, 0.092), a)
    shirt = skin_mesh('shirt', V, E, R, SHIRT)
    shirt.data.materials.append(TRIM)
    # Collar + sleeve cuffs get the trim colour.
    for p in shirt.data.polygons:
        c = p.center
        if c.z > 1.44: p.material_index = 1
        sleeve_end = SH + (EL - SH) * 0.5
        for sx in (1, -1):
            se = Vector((sx * sleeve_end.x, sleeve_end.y, sleeve_end.z))
            if (c - se).length < 0.075 and abs(c.x) > 0.25: p.material_index = 1
    return shirt

# ---------------------------------------------------------------- shorts
def build_shorts():
    V, E, R = [], [], []
    def add(p, r, parent=None):
        V.append(Vector(p)); R.append(r)
        i = len(V) - 1
        if parent is not None: E.append((parent, i))
        return i
    top = add((0, 0.003, 1.06), (0.18, 0.132))
    pel = add((0, 0.004, 0.9), (0.19, 0.138), top)
    for s in (1, -1):
        f = (lambda v: v) if s == 1 else mirror_x
        a = add(f(Vector((0.105, 0.004, 0.8))), 0.128, pel)
        add(f(Vector((0.118, 0.0, 0.6))), (0.128, 0.122), a)
    sh = skin_mesh('shorts', V, E, R, SHORTS)
    return sh

# ---------------------------------------------------------------- boots
def build_boot(s):
    f = (lambda v: v) if s == 1 else mirror_x
    V = [f(Vector((AN.x, 0.04, 0.085))), f(Vector((AN.x, -0.05, 0.07))), f(Vector((AN.x + 0.004, -0.15, 0.06))), f(Vector((AN.x, 0.0, 0.14)))]
    E = [(0, 1), (1, 2), (0, 3)]
    R = [(0.085, 0.09), (0.09, 0.085), (0.084, 0.064), 0.072]
    b = skin_mesh('boot' + ('L' if s == 1 else 'R'), V, E, R, BOOT)
    b.data.materials.append(SOLE)
    b.data.materials.append(ACCENT)
    for p in b.data.polygons:
        c = p.center
        if c.z < 0.03: p.material_index = 1
        elif abs(c.x - f(Vector((AN.x, 0, 0))).x) > 0.07 and c.z < 0.1 and c.y > -0.09: p.material_index = 2
    # Flatten the sole.
    for v in b.data.vertices:
        if v.co.z < 0.012: v.co.z = 0.012
    return b

# ---------------------------------------------------------------- hands
def build_hand(s):
    f = (lambda v: v) if s == 1 else mirror_x
    d = (WR - EL).normalized()
    V = [f(WR - d * 0.01), f(WR + d * 0.06), f(WR + d * 0.12), f(WR + d * 0.04 + Vector((0, -0.055, 0.012)))]
    E = [(0, 1), (1, 2), (1, 3)]
    R = [0.05, (0.064, 0.045), (0.056, 0.042), 0.028]
    h = skin_mesh('hand' + ('L' if s == 1 else 'R'), V, E, R, SKIN)
    return h

# ---------------------------------------------------------------- head
def build_head():
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=32, radius=HEAD_R, location=HEAD_C)
    head = bpy.context.active_object
    head.name = 'head'
    me = head.data
    for v in me.vertices:
        p = v.co.copy()           # local, centred
        t = max(0.0, -p.z / HEAD_R)   # 0 at centre line, 1 at bottom
        # Anime head: round cranium, tapered cheeks, soft pointed chin pushed forward.
        taper = 1 - 0.34 * t ** 1.6
        p.x *= 0.93 * taper
        p.y *= 0.95 * (1 - 0.18 * t)
        if p.y < 0: p.y *= 1.0 - 0.06 * (1 - t)   # flatter face plane
        p.z *= 1.04
        if t > 0.5: p.y -= 0.03 * (t - 0.5)          # chin forward
        v.co = p
    me.materials.append(HEADM)
    for poly in me.polygons: poly.use_smooth = True
    # UVs: cylindrical around Z, u=0.5 at the face (-Y), v by height.
    while me.uv_layers: me.uv_layers.remove(me.uv_layers[0])
    uv = me.uv_layers.new(name='UV')
    me.uv_layers.active = uv
    zs = [v.co.z for v in me.vertices]
    zmin, zmax = min(zs), max(zs)
    for poly in me.polygons:
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            u = 0.5 + math.atan2(co.x, -co.y) / (2 * math.pi)
            vv = (co.z - zmin) / (zmax - zmin)
            uv.data[li].uv = (u, vv)
    # Fix the seam (behind the head): faces straddling u=0/1.
    for poly in me.polygons:
        us = [uv.data[li].uv[0] for li in poly.loop_indices]
        if max(us) - min(us) > 0.5:
            for li in poly.loop_indices:
                if uv.data[li].uv[0] < 0.5: uv.data[li].uv[0] += 1.0
    # Ears.
    ears = []
    for s in (1, -1):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=10, radius=0.042, location=(s * HEAD_R * 0.9, 0.012, HEAD_C.z - 0.01))
        e = bpy.context.active_object
        e.scale = (0.45, 0.8, 1.0)
        bpy.ops.object.transform_apply(scale=True)
        e.data.materials.append(SKIN)
        for poly in e.data.polygons: poly.use_smooth = True
        ears.append(e)
    return head, ears

# ---------------------------------------------------------------- hair
_PROFILE = None
def lock_profile():
    """Flattened, slightly crescent cross-section so locks read as anime clumps, not cones."""
    global _PROFILE
    if _PROFILE: return _PROFILE
    cu = bpy.data.curves.new('lockprofile', 'CURVE')
    cu.dimensions = '2D'
    sp = cu.splines.new('POLY')
    pts = []
    for i in range(10):
        a = i / 10 * 2 * math.pi
        x = math.cos(a) * 0.1
        y = math.sin(a) * 0.07 + (0.02 * math.cos(a) ** 2 if math.sin(a) > 0 else 0)
        pts.append((x, y, 0, 1))
    sp.points.add(len(pts) - 1)
    for i, p in enumerate(pts): sp.points[i].co = p
    sp.use_cyclic_u = True
    _PROFILE = link(bpy.data.objects.new('lockprofile', cu))
    return _PROFILE

def strand(name, root, direction, length, radius, bend=Vector((0, 0, 0)), segs=4):
    cu = bpy.data.curves.new(name, 'CURVE')
    cu.dimensions = '3D'
    cu.bevel_mode = 'OBJECT'
    cu.bevel_object = lock_profile()
    cu.twist_mode = 'Z_UP'
    cu.use_map_taper = False
    cu.resolution_u = 4
    cu.use_fill_caps = True
    sp = cu.splines.new('BEZIER')
    sp.bezier_points.add(segs - 1)
    d = direction.normalized()
    for i, bp in enumerate(sp.bezier_points):
        t = i / (segs - 1)
        p = root + d * length * t + bend * (t * t) * length
        bp.co = p
        bp.handle_left_type = bp.handle_right_type = 'AUTO'
        bp.radius = radius / 0.1 * max(0.02, (1 - t) ** 0.8) * (1.15 if t < 0.3 else 1)
    ob = link(bpy.data.objects.new(name, cu))
    return ob

def sph(theta, phi, r=1.0):
    """theta from top pole, phi around (0 = face -Y)."""
    return Vector((math.sin(theta) * math.sin(phi), -math.sin(theta) * math.cos(phi), math.cos(theta))) * r

def hair_cap(front=1.05, back=1.9, side=1.55, scale=1.045):
    """Scalp shell: sphere cap hugging the cranium, lower at the back than the front."""
    bm = bmesh.new()
    rings, segs = 16, 40
    rows = []
    for r in range(rings + 1):
        row = []
        for s in range(segs):
            phi = s / segs * 2 * math.pi
            fz = math.cos(phi)   # 1 at face
            lim = side + ((front - side) * fz if fz >= 0 else (back - side) * -fz)
            th = r / rings * lim
            p = sph(th, phi, HEAD_R * scale)
            p.x *= 0.93; p.y *= 0.95; p.z *= 1.04
            row.append(bm.verts.new(p + HEAD_C))
        rows.append(row)
    for r in range(rings):
        for s in range(segs):
            a, b = rows[r][s], rows[r][(s + 1) % segs]
            c, d = rows[r + 1][(s + 1) % segs], rows[r + 1][s]
            try: bm.faces.new((a, b, c, d))
            except ValueError: pass
    me = bpy.data.meshes.new('cap')
    bm.to_mesh(me)
    ob = link(bpy.data.objects.new('cap', me))
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    sol = ob.modifiers.new('sol', 'SOLIDIFY'); sol.thickness = 0.018; sol.offset = 1
    bpy.ops.object.modifier_apply(modifier='sol')
    ob.select_set(False)
    for p in me.polygons: p.use_smooth = True
    return ob

def finish_hair(name, parts):
    objs = []
    for o in parts:
        if o.type == 'CURVE':
            bpy.context.view_layer.objects.active = o
            o.select_set(True)
            bpy.ops.object.convert(target='MESH')
            o.select_set(False)
        objs.append(o)
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    h = bpy.context.active_object
    h.name = 'hair_' + name
    h.data.materials.clear()
    h.data.materials.append(HAIR)
    for p in h.data.polygons: p.use_smooth = True
    h.select_set(False)
    return h

def hair_spiky():
    parts = [hair_cap(scale=1.06)]
    import random
    rnd = random.Random(4)
    # Big swept locks: crown flares up/back in chunky clumps.
    locks = [
        # (theta, phi, length, radius, dir tweak)
        (0.25, 0.0, 0.26, 0.07, (0, 0.25, 1.0)),
        (0.45, 0.6, 0.25, 0.068, (0.35, 0.3, 0.9)),
        (0.45, -0.6, 0.25, 0.068, (-0.35, 0.3, 0.9)),
        (0.6, 1.3, 0.22, 0.065, (0.8, 0.35, 0.55)),
        (0.6, -1.3, 0.22, 0.065, (-0.8, 0.35, 0.55)),
        (0.7, 2.0, 0.22, 0.062, (0.7, 0.8, 0.3)),
        (0.7, -2.0, 0.22, 0.062, (-0.7, 0.8, 0.3)),
        (0.6, 2.7, 0.24, 0.066, (0.25, 1.0, 0.25)),
        (0.6, -2.7, 0.24, 0.066, (-0.25, 1.0, 0.25)),
        (0.4, 3.14, 0.25, 0.07, (0, 0.9, 0.6)),
        (0.95, 2.4, 0.18, 0.055, (0.4, 0.9, -0.4)),
        (0.95, -2.4, 0.18, 0.055, (-0.4, 0.9, -0.4)),
        (1.1, 3.14, 0.16, 0.055, (0, 0.8, -0.6)),
        (0.35, 1.9, 0.2, 0.06, (0.3, 0.6, 1.0)),
        (0.35, -1.9, 0.2, 0.06, (-0.3, 0.6, 1.0)),
    ]
    for i, (th, ph, ln, rad, dv) in enumerate(locks):
        n = sph(th, ph)
        root = HEAD_C + Vector((n.x * HEAD_R * 0.8, n.y * HEAD_R * 0.8, n.z * HEAD_R * 0.85))
        d = Vector(dv).normalized()
        parts.append(strand(f's{i}', root, d, ln * 1.25, rad * 1.35, bend=Vector((0, 0.1, -0.12))))
    # Fringe: three thick locks sweeping across the forehead.
    for i, (x, dx) in enumerate(((-0.1, -0.35), (-0.02, 0.1), (0.075, 0.45))):
        root = HEAD_C + Vector((x, -HEAD_R * 0.55, HEAD_R * 0.82))
        parts.append(strand(f'f{i}', root, Vector((dx, -0.6, -0.8)), 0.19, 0.068, bend=Vector((dx * 0.3, -0.02, 0.05))))
    # Side burns.
    for s in (1, -1):
        root = HEAD_C + Vector((s * HEAD_R * 0.83, -0.03, HEAD_R * 0.25))
        parts.append(strand(f'side{s}', root, Vector((s * 0.15, -0.15, -1)), 0.16, 0.055))
    return finish_hair('spikes', parts)


def lock(name, th, ph, d, ln, rad, bend=(0, 0.05, -0.1), inset=0.82):
    n = sph(th, ph)
    root = HEAD_C + Vector((n.x * HEAD_R * inset, n.y * HEAD_R * inset, n.z * HEAD_R * inset))
    return strand(name, root, Vector(d), ln, rad, bend=Vector(bend))

def ball(name, center, r):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=10, ring_count=7, radius=r, location=center)
    o = bpy.context.active_object; o.name = name
    return o


def hairline(parts, n=6, length=0.1, rad=0.045, spread=1.0, seed=1):
    """Short tapered locks along the front hairline so caps never read as helmets."""
    import random
    rnd = random.Random(seed)
    for i in range(n):
        t = (i / (n - 1) - 0.5) * 2 * spread     # -spread..spread
        ph = t * 0.95
        n_ = sph(0.95, ph)
        root = HEAD_C + Vector((n_.x * HEAD_R * 0.98, n_.y * HEAD_R * 0.98, n_.z * HEAD_R * 1.0))
        d = Vector((math.sin(ph) * 0.35, -0.45, -1.0))
        parts.append(strand(f'hl{seed}_{i}', root, d, length * rnd.uniform(0.8, 1.25), rad, bend=Vector((0, -0.04, 0.02))))
    for s in (1, -1):
        root = HEAD_C + Vector((s * HEAD_R * 0.88, -0.02, HEAD_R * 0.3))
        parts.append(strand(f'tb{seed}{s}', root, Vector((s * 0.1, -0.1, -1)), length * 0.9, rad * 0.9))
    return parts

def hair_buzz():
    return finish_hair('buzz', [hair_cap(front=1.0, back=1.75, side=1.5, scale=1.025)])

def hair_crop():
    parts = [hair_cap(front=1.0, back=1.8, side=1.5, scale=1.05)]
    for i, ph in enumerate((-0.5, -0.2, 0.15, 0.45)):
        parts.append(lock(f'c{i}', 0.35, ph, (math.sin(ph) * 0.3, -0.7, 0.35), 0.12, 0.06))
    for i, ph in enumerate((1.4, 2.2, 3.0, -2.2, -1.4)):
        parts.append(lock(f't{i}', 0.45, ph, (math.sin(ph) * 0.4, math.cos(ph) * -0.4 + 0.3, 0.6), 0.1, 0.055))
    hairline(parts, n=6, length=0.09, seed=2)
    return finish_hair('crop', parts)

def hair_fringe():
    parts = [hair_cap(front=1.1, back=1.95, side=1.6, scale=1.07)]
    for i in range(7):
        x = -0.12 + i * 0.04
        root = HEAD_C + Vector((x, -HEAD_R * 0.45, HEAD_R * 0.88))
        parts.append(strand(f'f{i}', root, Vector((x * 0.8, -0.35, -1)), 0.2, 0.052, bend=Vector((0, -0.08, 0.02))))
    for s in (1, -1):
        for k in range(2):
            root = HEAD_C + Vector((s * HEAD_R * 0.85, -0.02 + k * 0.05, HEAD_R * 0.45))
            parts.append(strand(f's{s}{k}', root, Vector((s * 0.15, 0.05, -1)), 0.22, 0.055))
    for i, ph in enumerate((2.4, 2.9, 3.4, 3.9)):
        parts.append(lock(f'b{i}', 0.9, ph, (math.sin(ph) * 0.3, 0.4, -1), 0.2, 0.06))
    return finish_hair('fringe', parts)

def hair_afro():
    parts = [hair_cap(front=1.05, back=1.8, side=1.55, scale=1.04)]
    import random
    rnd = random.Random(9)
    for i in range(60):
        th = rnd.uniform(0, 1.35); ph = rnd.uniform(0, 2 * math.pi)
        if math.cos(ph) > 0.35 and th > 0.95: continue
        n = sph(th, ph)
        c = HEAD_C + Vector((n.x * 1.18, n.y * 1.15, n.z * 1.1)) * HEAD_R + Vector((0, 0.02, 0.05))
        parts.append(ball(f'a{i}', c, rnd.uniform(0.07, 0.1)))
    return finish_hair('afro', parts)

def hair_mohawk():
    parts = [hair_cap(front=1.0, back=1.7, side=1.45, scale=1.02)]
    for i in range(7):
        th = -0.75 + i * 0.3
        ph = 0.0 if th >= 0 else math.pi
        parts.append(lock(f'm{i}', abs(th), ph, (0, 0.35 + i * 0.12, 1.0), 0.24 - abs(i - 3) * 0.015, 0.1, bend=(0, 0.1, -0.05), inset=0.9))
    return finish_hair('mohawk', parts)

def hair_curls():
    parts = [hair_cap(front=1.05, back=1.8, side=1.55, scale=1.06)]
    import random
    rnd = random.Random(3)
    for i in range(34):
        th = rnd.uniform(0.05, 1.05); ph = rnd.uniform(0, 2 * math.pi)
        if math.cos(ph) > 0.6 and th > 0.8: continue
        n = sph(th, ph)
        c = HEAD_C + n * HEAD_R * 1.08
        parts.append(ball(f'k{i}', c, rnd.uniform(0.045, 0.06)))
    return finish_hair('curls', parts)

def hair_locs():
    parts = [hair_cap(front=1.05, back=1.85, side=1.55, scale=1.06)]
    for i in range(18):
        ph = i / 18 * 2 * math.pi
        if math.cos(ph) > 0.7: continue
        ln = 0.36 if math.cos(ph) < -0.2 else 0.26
        parts.append(lock(f'l{i}', 0.75, ph, (math.sin(ph) * 0.45, math.cos(ph) * -0.25 + 0.2, -1), ln, 0.065, bend=(0, 0.02, -0.02), inset=1.0))
    for i in range(6):
        ph = (i - 2.5) * 0.3
        parts.append(lock(f'top{i}', 0.2, ph, (math.sin(ph) * 0.6, -0.5, -0.4), 0.18, 0.05))
    hairline(parts, n=5, length=0.12, rad=0.05, seed=6)
    return finish_hair('locs', parts)

def hair_bun():
    parts = [hair_cap(front=1.1, back=1.85, side=1.55, scale=1.04)]
    parts.append(ball('bun', HEAD_C + Vector((0, 0.1, HEAD_R * 1.12)), 0.1))
    for s in (1, -1):
        root = HEAD_C + Vector((s * HEAD_R * 0.7, -HEAD_R * 0.55, HEAD_R * 0.6))
        parts.append(strand(f'fr{s}', root, Vector((s * 0.2, -0.3, -1)), 0.2, 0.04))
    hairline(parts, n=5, length=0.11, seed=3)
    return finish_hair('bun', parts)

def hair_ponytail():
    parts = [hair_cap(front=1.1, back=1.85, side=1.55, scale=1.05)]
    root = HEAD_C + Vector((0, HEAD_R * 0.95, HEAD_R * 0.35))
    parts.append(strand('tail', root, Vector((0, 0.5, -1)), 0.45, 0.085, bend=Vector((0, 0.15, 0.05))))
    for i, x in enumerate((-0.08, 0.0, 0.08)):
        root = HEAD_C + Vector((x, -HEAD_R * 0.55, HEAD_R * 0.8))
        parts.append(strand(f'f{i}', root, Vector((x * 2, -0.5, -0.9)), 0.15, 0.05))
    hairline(parts, n=5, length=0.11, seed=4)
    return finish_hair('ponytail', parts)

def hair_hightop():
    parts = [hair_cap(front=1.0, back=1.7, side=1.45, scale=1.03)]
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=HEAD_R * 0.9, depth=0.2, location=HEAD_C + Vector((0, 0.01, HEAD_R * 0.98)))
    cyl = bpy.context.active_object
    bev = cyl.modifiers.new('bev', 'BEVEL'); bev.width = 0.04; bev.segments = 4
    bpy.context.view_layer.objects.active = cyl; cyl.select_set(True)
    bpy.ops.object.modifier_apply(modifier='bev'); cyl.select_set(False)
    parts.append(cyl)
    return finish_hair('highTop', parts)

def hair_cornrows():
    parts = [hair_cap(front=1.0, back=1.8, side=1.5, scale=1.025)]
    for i in range(6):
        x = (i - 2.5) * 0.05
        pts = []
        cu = bpy.data.curves.new(f'row{i}', 'CURVE'); cu.dimensions = '3D'; cu.bevel_depth = 0.022; cu.bevel_resolution = 2
        sp = cu.splines.new('POLY'); sp.points.add(9)
        for k in range(10):
            th = -1.0 + k * 0.28
            n = sph(abs(th), 0 if th < 0 else math.pi)
            p = HEAD_C + Vector((x, n.y * HEAD_R * 1.05, n.z * HEAD_R * 1.05))
            sp.points[k].co = (p.x, p.y, p.z, 1)
        parts.append(link(bpy.data.objects.new(f'row{i}', cu)))
    return finish_hair('cornrows', parts)

def hair_mullet():
    parts = [hair_cap(front=1.05, back=2.05, side=1.55, scale=1.06)]
    for i, ph in enumerate((-0.4, 0.0, 0.4)):
        parts.append(lock(f'f{i}', 0.4, ph, (math.sin(ph) * 0.4, -0.7, 0.2), 0.13, 0.06))
    for i, x in enumerate((-0.1, -0.035, 0.035, 0.1)):
        root = HEAD_C + Vector((x, HEAD_R * 0.8, -HEAD_R * 0.2))
        parts.append(strand(f'b{i}', root, Vector((x, 0.3, -1)), 0.22, 0.06))
    hairline(parts, n=6, length=0.1, seed=5)
    return finish_hair('mullet', parts)

# ---------------------------------------------------------------- armature
BONES = {}
def build_armature():
    arm = bpy.data.armatures.new('rig')
    ob = link(bpy.data.objects.new('rig', arm))
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm.edit_bones
    def bone(name, head, tail, parent=None, roll=0):
        b = eb.new(name)
        b.head = head; b.tail = tail; b.roll = roll
        if parent: b.parent = eb[parent]; b.use_connect = False
        return b
    bone('hips', (0, 0, 0.9), (0, 0, 1.05))
    bone('spine', (0, 0, 1.05), (0, 0, 1.24), 'hips')
    bone('chest', (0, 0, 1.24), (0, 0, 1.42), 'spine')
    bone('neck', (0, 0.005, 1.42), (0, 0.01, 1.53), 'chest')
    bone('head', (0, 0.01, 1.53), (0, 0.01, 1.95), 'neck')
    for s, side in ((1, 'L'), (-1, 'R')):
        f = (lambda v: v) if s == 1 else mirror_x
        bone('upperarm.' + side, f(SH), f(EL), 'chest')
        bone('forearm.' + side, f(EL), f(WR), 'upperarm.' + side)
        bone('hand.' + side, f(WR), f(WR + (WR - EL).normalized() * 0.1), 'forearm.' + side)
        bone('thigh.' + side, f(HP), f(KN), 'hips')
        bone('shin.' + side, f(KN), f(AN), 'thigh.' + side)
        bone('foot.' + side, f(AN), f(Vector((AN.x, -0.13, 0.03))), 'shin.' + side)
    bpy.ops.object.mode_set(mode='OBJECT')
    ob.select_set(False)
    return ob

def auto_weight(obj, rig):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type='ARMATURE_AUTO')
    bpy.ops.object.select_all(action='DESELECT')

def rigid_weight(obj, rig, bone):
    obj.parent = rig
    vg = obj.vertex_groups.new(name=bone)
    vg.add([v.index for v in obj.data.vertices], 1.0, 'REPLACE')
    mod = obj.modifiers.new('rig', 'ARMATURE')
    mod.object = rig

# ---------------------------------------------------------------- build
rig = build_armature()
body = build_body()
shirt = build_shirt()
shorts = build_shorts()
boots = [build_boot(1), build_boot(-1)]
hands = [build_hand(1), build_hand(-1)]
head, ears = build_head()
hairs = {}
for fn in (hair_spiky, hair_buzz, hair_crop, hair_fringe, hair_afro, hair_mohawk, hair_curls, hair_locs, hair_bun, hair_ponytail, hair_hightop, hair_cornrows, hair_mullet):
    h = fn()
    hairs[h.name[5:]] = h

for o in (body, shirt, shorts):
    auto_weight(o, rig)
rigid_weight(boots[0], rig, 'foot.L'); rigid_weight(boots[1], rig, 'foot.R')
rigid_weight(hands[0], rig, 'hand.L'); rigid_weight(hands[1], rig, 'hand.R')
rigid_weight(head, rig, 'head')
for e in ears: rigid_weight(e, rig, 'head')
for h in hairs.values(): rigid_weight(h, rig, 'head')

print('built', [o.name for o in scene.objects])

# ---------------------------------------------------------------- preview render
def preview(path, angle=0.0):
    scene.render.engine = 'BLENDER_WORKBENCH'
    sh = scene.display.shading
    sh.light = 'STUDIO'
    sh.color_type = 'MATERIAL'
    sh.show_object_outline = True
    sh.object_outline_color = (0.05, 0.05, 0.08)
    sh.show_cavity = True
    sh.show_shadows = True
    scene.render.resolution_x = 900
    scene.render.resolution_y = 1100
    scene.render.film_transparent = False
    world = bpy.data.worlds.new('w'); scene.world = world
    cam_data = bpy.data.cameras.new('cam')
    cam_data.lens = 85
    cam = link(bpy.data.objects.new('cam', cam_data))
    d = 5.2
    cam.location = (math.sin(angle) * d, -math.cos(angle) * d, 1.05)
    cam.rotation_euler = (math.radians(90), 0, angle)
    scene.camera = cam
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)

if '--preview' in ARGS:
    preview(os.path.join(OUT, 'preview_front.png'), 0.0)
    preview(os.path.join(OUT, 'preview_34.png'), math.radians(35))
    preview(os.path.join(OUT, 'preview_back.png'), math.radians(180))

# ---------------------------------------------------------------- export
def to_scn(v):
    return [round(v[0], 5), round(v[2], 5), round(-v[1], 5)]

C = Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, -1, 0, 0), (0, 0, 0, 1)))

def kit_uv(co, zmin, zmax):
    a = math.atan2(-co.x, co.y)
    u = ((a + math.pi / 2) / (2 * math.pi)) % 1.0
    v = (co.z - zmin) / (zmax - zmin)
    return (u, v)

def export_mesh(obj, rig, slot, uvmode):
    bone_names = [b.name for b in rig.data.bones]
    dg = bpy.context.evaluated_depsgraph_get()
    # Use the un-deformed mesh (armature modifier would pose it).
    me = obj.data.copy()
    me.transform(obj.matrix_world)
    bm = bmesh.new(); bm.from_mesh(me); bmesh.ops.triangulate(bm, faces=bm.faces[:]); bm.to_mesh(me); bm.free()
    me.calc_loop_triangles() if hasattr(me, 'calc_loop_triangles') else None
    uvl = me.uv_layers.active
    zs = [v.co.z for v in me.vertices]
    zmin, zmax = (0.85, 1.5) if uvmode == 'kit' else (min(zs), max(zs))
    groups = {g.index: g.name for g in obj.vertex_groups}
    positions, normals, uvs, joints, weights = [], [], [], [], []
    index_of = {}
    per_mat = {}
    corner_normals = me.corner_normals if hasattr(me, 'corner_normals') else None
    for poly in me.polygons:
        tri = []
        us = []
        for li in poly.loop_indices:
            vi = me.loops[li].vertex_index
            co = me.vertices[vi].co
            if uvmode == 'uv' and uvl: uv = tuple(uvl.data[li].uv)
            elif uvmode == 'kit': uv = kit_uv(co, zmin, zmax)
            else: uv = (0.5, (co.z - zmin) / max(1e-5, zmax - zmin))
            us.append(uv)
        if uvmode == 'kit' and max(u[0] for u in us) - min(u[0] for u in us) > 0.5:
            us = [(u[0] + 1 if u[0] < 0.5 else u[0], u[1]) for u in us]
        for k, li in enumerate(poly.loop_indices):
            vi = me.loops[li].vertex_index
            n = corner_normals[li].vector if corner_normals is not None else me.vertices[vi].normal
            uv = us[k]
            key = (vi, round(uv[0], 4), round(uv[1], 4), round(n.x, 2), round(n.y, 2), round(n.z, 2))
            if key not in index_of:
                index_of[key] = len(positions)
                positions.append(to_scn(me.vertices[vi].co))
                normals.append(to_scn(n.normalized()))
                uvs.append([round(uv[0], 4), round(1 - uv[1], 4)])
                ws = []
                for g in me.vertices[vi].groups:
                    name = groups.get(g.group)
                    if name in bone_names and g.weight > 0.001: ws.append((g.weight, bone_names.index(name)))
                ws.sort(reverse=True)
                ws = ws[:4]
                tot = sum(w for w, _ in ws) or 1
                ws = [(w / tot, b) for w, b in ws] + [(0, 0)] * (4 - len(ws))
                joints.append([b for _, b in ws]); weights.append([round(w, 4) for w, _ in ws])
            tri.append(index_of[key])
        mname = obj.data.materials[poly.material_index].name if obj.data.materials else 'skin'
        per_mat.setdefault(mname, []).extend(tri)
    bpy.data.meshes.remove(me)
    return {'name': obj.name, 'slot': slot, 'positions': [c for p in positions for c in p], 'normals': [c for p in normals for c in p],
            'uvs': [c for p in uvs for c in p], 'joints': [c for j in joints for c in j], 'weights': [c for w in weights for c in w],
            'groups': [{'material': m, 'indices': idx} for m, idx in per_mat.items()]}

def export(path):
    bones = []
    names = [b.name for b in rig.data.bones]
    for b in rig.data.bones:
        m = C @ b.matrix_local @ C.transposed()
        bones.append({'name': b.name, 'parent': names.index(b.parent.name) if b.parent else -1,
                      'matrix': [round(m[r][c], 6) for c in range(4) for r in range(4)]})   # column-major
    meshes = [
        export_mesh(body, rig, 'body', 'none'),
        export_mesh(shirt, rig, 'shirt', 'kit'),
        export_mesh(shorts, rig, 'shorts', 'kit'),
        export_mesh(boots[0], rig, 'boots', 'none'), export_mesh(boots[1], rig, 'boots', 'none'),
        export_mesh(hands[0], rig, 'hands', 'none'), export_mesh(hands[1], rig, 'hands', 'none'),
        export_mesh(head, rig, 'head', 'uv'),
        export_mesh(ears[0], rig, 'ears', 'none'), export_mesh(ears[1], rig, 'ears', 'none'),
    ]
    for name, h in hairs.items():
        meshes.append(export_mesh(h, rig, 'hair:' + name, 'none'))
    # Binary layout: u32 headerLen | header JSON | pad to 4 | blob.
    import struct
    blob = bytearray()
    def put(fmt, arr):
        off = len(blob)
        blob.extend(struct.pack('<%d%s' % (len(arr), fmt), *arr))
        while len(blob) % 4: blob.append(0)
        return off
    meta = []
    for m in meshes:
        n = len(m['positions']) // 3
        e = {'name': m['name'], 'slot': m['slot'], 'count': n,
             'pos': put('f', m['positions']), 'nor': put('f', m['normals']), 'uv': put('f', m['uvs']),
             'joints': put('H', m['joints']), 'weights': put('f', m['weights']), 'groups': []}
        for g in m['groups']:
            e['groups'].append({'material': g['material'], 'offset': put('H', g['indices']), 'count': len(g['indices'])})
        meta.append(e)
    header = json.dumps({'version': 2, 'bones': bones, 'meshes': meta, 'headCenter': to_scn(HEAD_C), 'headRadius': HEAD_R}, separators=(',', ':')).encode()
    while (4 + len(header)) % 4: header += b' '
    with open(path, 'wb') as f:
        f.write(struct.pack('<I', len(header))); f.write(header); f.write(blob)
    print('exported', path, os.path.getsize(path), 'bytes', sum(len(m['positions']) // 3 for m in meshes), 'verts')

if '--export' in ARGS:
    dest = os.path.join(ROOT, 'Panna', 'Resources', 'Characters')
    os.makedirs(dest, exist_ok=True)
    export(os.path.join(dest, 'base.bin'))
    old = os.path.join(dest, 'base.json')
    if os.path.exists(old): os.remove(old)
