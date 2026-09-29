"""Blender headless: decimate + fit a humanoid armature to an A-pose image-to-3D mesh, auto-weight, test pose, render.
Usage: Blender -b proj.blend -P autorig.py -- out_prefix target_tris
Joint positions come from landmarks measured on the 1024x1536 reference (figure bbox x316-695, y229-1319),
mapped to the mesh bbox; bone depth (Y) is the mean Y of mesh verts near each joint."""
import bpy, sys, math, bmesh
from mathutils import Vector, Euler
argv = sys.argv[sys.argv.index('--')+1:]; prefix = argv[0]; target = int(argv[1])
obj = next(o for o in bpy.context.scene.objects if o.type == 'MESH')
bpy.context.view_layer.objects.active = obj; obj.select_set(True)
# apply transforms so mesh space == world
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
n0 = len(obj.data.polygons)
dec = obj.modifiers.new("dec", 'DECIMATE'); dec.ratio = min(1.0, target/n0)
bpy.ops.object.modifier_apply(modifier="dec")
print("RIG decimated", n0, "->", len(obj.data.polygons), "tris")
ws = [Vector(c) for c in obj.bound_box]
mn = Vector([min(p[i] for p in ws) for i in range(3)]); mx = Vector([max(p[i] for p in ws) for i in range(3)])
X0,X1,Y0,Y1 = 316,695,229,1319
def W(px, py):  # image px -> world x,z
    return mn.x + (px-X0)/(X1-X0)*(mx.x-mn.x), mx.z - (py-Y0)/(Y1-Y0)*(mx.z-mn.z)
verts = [v.co.copy() for v in obj.data.vertices]
def J(px, py, r=0.05):
    x, z = W(px, py)
    near = [v.y for v in verts if abs(v.z-z) < r and abs(v.x-x) < r]
    return Vector((x, sum(near)/len(near) if near else (mn.y+mx.y)/2, z))
cx = 508
L = {  # image-left = character right (.R), mirrored for .L
 'hips': (cx, 800), 'spine': (cx, 700), 'chest': (cx, 590), 'neck': (cx, 495), 'head': (cx, 460), 'head_end': (cx, 235),
 'shoulder': (395, 505), 'elbow': (352, 690), 'wrist': (330, 850), 'hand_end': (330, 905),
 'hip': (462, 810), 'knee': (445, 1030), 'ankle': (428, 1255), 'toe': (428, 1305)}
def P(name, side=None):
    px, py = L[name]
    if side == 'L': px = 2*cx - px
    return J(px, py)
arm = bpy.data.armatures.new("rig"); ro = bpy.data.objects.new("rig", arm); bpy.context.scene.collection.objects.link(ro)
bpy.ops.object.select_all(action='DESELECT'); bpy.context.view_layer.objects.active = ro; ro.select_set(True)
bpy.ops.object.mode_set(mode='EDIT'); eb = arm.edit_bones
def bone(name, h, t, parent=None, connect=False):
    b = eb.new(name); b.head, b.tail = h, t
    if parent: b.parent = eb[parent]; b.use_connect = connect
    return b
bone('hips', P('hips'), P('spine'))
bone('spine', P('spine'), P('chest'), 'hips', True)
bone('chest', P('chest'), P('neck'), 'spine', True)
bone('neck', P('neck'), P('head'), 'chest', True)
bone('head', P('head'), P('head_end'), 'neck', True)
for s in ('L', 'R'):
    sd = s if s == 'L' else None
    bone(f'upperarm.{s}', P('shoulder', sd), P('elbow', sd), 'chest')
    bone(f'forearm.{s}', P('elbow', sd), P('wrist', sd), f'upperarm.{s}', True)
    bone(f'hand.{s}', P('wrist', sd), P('hand_end', sd), f'forearm.{s}', True)
    bone(f'thigh.{s}', P('hip', sd), P('knee', sd), 'hips')
    bone(f'shin.{s}', P('knee', sd), P('ankle', sd), f'thigh.{s}', True)
    ft = P('toe', sd); ft.y = mn.y + 0.02
    bone(f'foot.{s}', P('ankle', sd), ft, f'shin.{s}', True)
# knees/elbows: nudge joints so they bend the right way
for s in ('L','R'):
    eb[f'shin.{s}'].head.y -= 0.01; eb[f'forearm.{s}'].head.y += 0.01
bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.object.select_all(action='DESELECT'); obj.select_set(True); ro.select_set(True); bpy.context.view_layer.objects.active = ro
bpy.ops.object.parent_set(type='ARMATURE_AUTO')
names = [b.name for b in arm.bones]
wsum = [0.0]*len(obj.data.vertices); per = {n: 0 for n in names}
gi = {g.index: g.name for g in obj.vertex_groups}
for v in obj.data.vertices:
    for g in v.groups:
        if g.weight > 0.01: wsum[v.index] += g.weight; per[gi[g.group]] += 1
zero = sum(1 for w in wsum if w < 0.01)
print("RIG verts", len(wsum), "unweighted", zero, f"({100*zero/len(wsum):.1f}%)")
print("RIG per-bone vert counts", per)
# test pose: arms down, left leg forward (kick prep), slight knee bend
pb = ro.pose.bones
for b in pb: b.rotation_mode = 'XYZ'
bpy.context.view_layer.update()
def rot_world(pbname, axis, deg):
    b = pb[pbname]; M = ro.matrix_world @ b.bone.matrix_local
    ax = M.to_3x3().inverted() @ Vector(axis)
    b.rotation_mode = 'AXIS_ANGLE'; b.rotation_axis_angle = (math.radians(deg), ax.x, ax.y, ax.z)
rot_world('upperarm.L', (0,1,0), 12); rot_world('upperarm.R', (0,1,0), -12)   # bring arms closer to body
rot_world('thigh.L', (1,0,0), -40)   # swing left leg forward (-Y)
rot_world('shin.L', (1,0,0), 35)     # bend knee
rot_world('thigh.R', (1,0,0), 10)
rot_world('forearm.L', (1,0,0), -10); rot_world('forearm.R', (1,0,0), -10)
rot_world('head', (0,0,1), 10)
bpy.context.view_layer.update()
scene = bpy.context.scene; cam = scene.camera
ctr = (mn+mx)/2
for name, deg in (('front', 0), ('three_quarter', 40), ('side', 90)):
    a = math.radians(deg); d = Vector((math.sin(a), -math.cos(a), 0))
    cam.location = ctr + d*5; cam.rotation_euler = (-d).to_track_quat('-Z','Y').to_euler()
    scene.render.filepath = f"{prefix}_{name}.png"; bpy.ops.render.render(write_still=True); print("RENDERED", scene.render.filepath)
ro.hide_render = True
bpy.ops.wm.save_as_mainfile(filepath=f"{prefix}.blend")
