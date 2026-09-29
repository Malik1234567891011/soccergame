"""Blender headless renders of an image-to-3D mesh.
Usage: Blender -b -P render_views.py -- model.glb out_prefix [--project ref.png x0 x1 y0 y1 FRONT_SIGN] [--blend out.blend]
--project: planar front-projects ref.png (figure pixel bbox x0..x1, y0..y1) onto the mesh as a texture proxy.
Back-facing faces above the chin get the hair colour so the face isn't printed on the back of the head."""
import bpy, sys, math, bmesh
from mathutils import Vector
argv = sys.argv[sys.argv.index('--')+1:]
path, prefix = argv[0], argv[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=path)
obj = [o for o in bpy.context.scene.objects if o.type == 'MESH'][0]
bpy.context.view_layer.objects.active = obj
ws = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
mn = Vector([min(p[i] for p in ws) for i in range(3)]); mx = Vector([max(p[i] for p in ws) for i in range(3)])
ctr = (mn+mx)/2; H = mx.z-mn.z
front_sign = -1.0
if '--project' in argv:
    k = argv.index('--project'); ref = argv[k+1]; x0,x1,y0,y1 = map(float, argv[k+2:k+6]); front_sign = float(argv[k+6])
    img = bpy.data.images.load(ref); W, Hh = img.size
    me = obj.data
    uv = me.uv_layers.new(name="proj")
    obj.matrix_world.identity() if False else None
    mat_img = bpy.data.materials.new("proj"); mat_img.use_nodes = True
    nt = mat_img.node_tree; bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    tex = nt.nodes.new('ShaderNodeTexImage'); tex.image = img; tex.interpolation = 'Closest' if False else 'Linear'
    em = nt.nodes.new('ShaderNodeEmission'); out = next(n for n in nt.nodes if n.type == 'OUTPUT_MATERIAL')
    nt.links.new(tex.outputs['Color'], em.inputs['Color']); nt.links.new(em.outputs[0], out.inputs['Surface'])
    hair = bpy.data.materials.new("hair_back"); hair.use_nodes = True
    ht = hair.node_tree; he = ht.nodes.new('ShaderNodeEmission'); he.inputs['Color'].default_value = (0.62,0.63,0.66,1)
    ht.links.new(he.outputs[0], next(n for n in ht.nodes if n.type=='OUTPUT_MATERIAL').inputs['Surface'])
    hair.diffuse_color = (0.62,0.63,0.66,1)
    me.materials.clear(); me.materials.append(mat_img); me.materials.append(hair)
    chin_z = mx.z - 0.233*H
    mw = obj.matrix_world
    for p in me.polygons:
        n = (mw.to_3x3() @ p.normal)
        c = mw @ p.center
        if n.y*front_sign < -0.15 and c.z > chin_z and abs(c.x-ctr.x) < 0.12*H: p.material_index = 1
        for li in p.loop_indices:
            v = mw @ me.vertices[me.loops[li].vertex_index].co
            fx = (v.x-mn.x)/(mx.x-mn.x); fz = (v.z-mn.z)/(mx.z-mn.z)
            if front_sign > 0: fx = 1-fx
            px = x0 + fx*(x1-x0); py = y1 - fz*(y1-y0)
            uv.data[li].uv = (px/W, 1-py/Hh)
scene = bpy.context.scene
try: scene.render.engine = 'BLENDER_WORKBENCH'
except TypeError as e: print(e)
sh = scene.display.shading
sh.light = 'FLAT' if '--project' in argv else 'STUDIO'
sh.color_type = 'TEXTURE' if '--project' in argv else 'SINGLE'
sh.single_color = (0.8,0.8,0.8)
sh.show_cavity = '--project' not in argv
sh.show_object_outline = True; sh.object_outline_color = (0,0,0)
scene.display.shading.background_type = 'VIEWPORT' if False else scene.display.shading.background_type
w = bpy.data.worlds.new("w"); scene.world = w; w.color = (0.85,0.85,0.87)
scene.render.resolution_x, scene.render.resolution_y = 768, 1024
try: scene.view_settings.view_transform = 'Standard'
except TypeError as e: print(e)
scene.render.film_transparent = False
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); scene.collection.objects.link(cam); scene.camera = cam
cam.data.type = 'ORTHO'; cam.data.ortho_scale = H*1.1
views = {'front': 0, 'three_quarter': 35, 'side': 90, 'back': 180}
for name, deg in views.items():
    a = math.radians(deg)
    d = Vector((math.sin(a), front_sign*math.cos(a), 0))  # direction from center to camera
    cam.location = ctr + d*5
    cam.rotation_euler = (-d).to_track_quat('-Z','Y').to_euler()
    scene.render.filepath = f"{prefix}_{name}.png"
    bpy.ops.render.render(write_still=True)
    print("RENDERED", scene.render.filepath)
if '--blend' in argv:
    bpy.ops.wm.save_as_mainfile(filepath=argv[argv.index('--blend')+1])
