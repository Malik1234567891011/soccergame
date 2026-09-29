#!/bin/zsh
# Re-bake every painted character at a lighter triangle budget (same textures pipeline).
cd ${0:A:h}
B=/Applications/Blender.app/Contents/MacOS/Blender
TRIS=${TRIS:-14000}
bake() {
  id=$1; mesh=$2; front=$3
  side=(); [ -f ${id}_ref_left.png ] && side+=(--left $PWD/${id}_ref_left.png); [ -f ${id}_ref_right.png ] && side+=(--right $PWD/${id}_ref_right.png)
  $B -b -P ../blender/unique.py -- --mesh $PWD/$mesh --front $PWD/$front --back $PWD/${id}_ref_back.png $side --name $id --tris $TRIS 2>&1 | grep -E "UNIQUE exported|Traceback"
}
pbake() {
  id=$1; mesh=$2
  front=${id}_ck_front.png; back=${id}_ck_back.png
  # Meshes generated from the code-kit art itself match its proportions and pose.
  [ -f ${id}_ck_shape.glb ] && mesh=${id}_ck_shape.glb
  [ -f $front ] || front=${id}_ref_front.png
  [ -f $back ] || back=${id}_ref_back.png
  side=(); [ -f ${id}_ref_left.png ] && side+=(--left $PWD/${id}_ref_left.png); [ -f ${id}_ref_right.png ] && side+=(--right $PWD/${id}_ref_right.png)
  $B -b -P ../blender/unique.py -- --mesh $PWD/$mesh --front $PWD/$front --back $PWD/$back $side --name $id --tris $TRIS 2>&1 | grep -E "UNIQUE exported|Traceback"
}
pbake luna luna_hy2_shape.glb &
for id in kairo vega amara sora demba odin rex juno niko zeke amir; do
  [ -n "$ONLY_LOOKS" ] && break
  pbake $id ${id}_shape.glb &
  while [ $(jobs -r | wc -l) -ge 3 ]; do sleep 2; done
done
[ -n "$ONLY_PROSPECTS" ] && { wait; echo "REBAKE DONE $(date +%T)"; exit 0; }
for f in l[0-9]*_ref_front.png; do
  id=${f%_ref_front.png}
  bake $id ${id}_shape.glb $f &
  while [ $(jobs -r | wc -l) -ge 3 ]; do sleep 2; done
done
wait
echo "REBAKE DONE $(date +%T)"
