#!/bin/zsh
cd ${0:A:h}
for f in l[0-9]*_ref_front.png; do
  id=${f%_ref_front.png}
  [ -f ${id}_shape.glb ] && continue
  echo "shape $id"; /private/tmp/ai3dvenv/bin/python run_hy2_shape.py $f ${id}_shape.glb 2>&1 | tail -1
done
./bake_roster.sh
