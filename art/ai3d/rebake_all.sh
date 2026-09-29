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
bake luna luna_hy2_shape.glb luna_ref_apose.png &
for id in kairo vega amara sora demba odin rex juno niko zeke amir; do
  bake $id ${id}_shape.glb ${id}_ref_front.png &
  while [ $(jobs -r | wc -l) -ge 3 ]; do sleep 2; done
done
for f in l[0-9]*_ref_front.png; do
  id=${f%_ref_front.png}
  bake $id ${id}_shape.glb $f &
  while [ $(jobs -r | wc -l) -ge 3 ]; do sleep 2; done
done
wait
echo "REBAKE DONE $(date +%T)"
