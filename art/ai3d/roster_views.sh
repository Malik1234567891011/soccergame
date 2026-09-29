#!/bin/zsh
cd ${0:A:h}
PY=/private/tmp/ai3dvenv/bin/python
BASE="Character model sheet of the exact same anime character, identical outfit (red jersey with yellow collar and cuffs, blue shorts, green socks, black boots), identical hair, skin and body proportions, same light A-pose, same scale and framing, full body centred with the same padding, plain light grey background, cel-shaded anime style with clean line art. No text."
for f in l*_ref_front.png; do
  id=${f%_ref_front.png}
  [ -f ${id}_ref_back.png ] || $PY make_ref.py $f ${id}_ref_back.png "$BASE View: seen from DIRECTLY BEHIND (back view): the back of the head and hair, the back of the jersey, shorts, calves and boot heels." 1024x1536 &
  [ -f ${id}_ref_left.png ] || $PY make_ref.py $f ${id}_ref_left.png "$BASE View: strict SIDE PROFILE, the character faces the RIGHT edge of the image, arms slightly away from the body." 1024x1536 &
  wait
done
echo VIEWS DONE
