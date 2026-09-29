"""Blender headless: import GLB, print stats. Usage: Blender -b -P inspect_glb.py -- model.glb"""
import bpy, bmesh, sys
from mathutils import Vector
path = sys.argv[sys.argv.index('--')+1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=path)
for o in [o for o in bpy.context.scene.objects if o.type == 'MESH']:
    me = o.data
    bm = bmesh.new(); bm.from_mesh(me)
    nm_e = sum(1 for e in bm.edges if not e.is_manifold)
    bnd = sum(1 for e in bm.edges if e.is_boundary)
    nm_v = sum(1 for v in bm.verts if not v.is_manifold)
    # loose parts
    seen=set(); parts=0
    for v in bm.verts:
        if v.index in seen: continue
        parts+=1; stack=[v]; seen.add(v.index)
        while stack:
            x=stack.pop()
            for e in x.link_edges:
                y=e.other_vert(x)
                if y.index not in seen: seen.add(y.index); stack.append(y)
    ws = [o.matrix_world @ Vector(c) for c in o.bound_box]
    mn = Vector((min(p.x for p in ws),min(p.y for p in ws),min(p.z for p in ws))); mx = Vector((max(p.x for p in ws),max(p.y for p in ws),max(p.z for p in ws)))
    print(f"STAT {o.name}: verts={len(me.vertices)} faces={len(me.polygons)} tris={sum(len(p.vertices)-2 for p in me.polygons)} "
          f"nonmanifold_edges={nm_e} boundary_edges={bnd} nonmanifold_verts={nm_v} loose_parts={parts} watertight={nm_e==0}")
    print(f"STAT bbox min={tuple(round(c,3) for c in mn)} max={tuple(round(c,3) for c in mx)} size={tuple(round(c,3) for c in (mx-mn))}")
    print(f"STAT uv_layers={[u.name for u in me.uv_layers]} color_attrs={[a.name for a in me.color_attributes]} materials={[m.name if m else None for m in me.materials]}")
    for m in me.materials:
        if m and m.use_nodes:
            print("STAT texnodes", [(n.image.name, tuple(n.image.size)) for n in m.node_tree.nodes if n.type=='TEX_IMAGE' and n.image])
