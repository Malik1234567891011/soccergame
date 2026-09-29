#!/bin/zsh
# Bake roster looks onto the best-matching Prospect body (until they get their own AI meshes).
cd ${0:A:h}
until grep -q "VIEWS DONE" /tmp/roster_views.log 2>/dev/null; do sleep 10; done
PY=/private/tmp/ai3dvenv/bin/python
B=/Applications/Blender.app/Contents/MacOS/Blender
FRONTS=()
for p in kairo luna vega amara sora demba odin rex juno niko zeke amir; do
  [ $p = luna ] && FRONTS+=(luna_ref_apose.png) || FRONTS+=(${p}_ref_front.png)
done
for f in l[0-9]*_ref_front.png; do
  id=${f%_ref_front.png}
  best=$($PY match_body.py $f $FRONTS)
  base=${best%_ref_*}
  mesh=${base}_shape.glb; [ $base = luna ] && mesh=luna_hy2_shape.glb
  [ -f ${id}_shape.glb ] && mesh=${id}_shape.glb
  echo "=== $id on $base body"
  $B -b -P ../blender/unique.py -- --mesh $PWD/$mesh --front $PWD/$f --back $PWD/${id}_ref_back.png --left $PWD/${id}_ref_left.png --name $id 2>&1 | grep -E "UNIQUE exported|Traceback|Error"
  sips -c 440 440 --cropOffset 170 292 $f --out /tmp/crop_$id.png >/dev/null 2>&1
  sips -s format jpeg -s formatOptions 82 -Z 220 /tmp/crop_$id.png --out ../../Panna/Resources/Portraits/look_$id.jpg >/dev/null 2>&1
done
echo "ROSTER BAKED $(date +%T)"
