#!/bin/zsh
# Repaint each Prospect's model sheets in the recolourable code kit (identity unchanged).
cd ${0:A:h}
PY=/private/tmp/ai3dvenv/bin/python
KIT="Change ONLY the clothing colours, keep the character's face, hair, skin, body, pose, framing, scale, background and art style exactly identical. New outfit colours: plain flat saturated pure RED short-sleeved football jersey with bright YELLOW V-collar and YELLOW sleeve cuffs, no stripes, no logos, no numbers; plain saturated pure BLUE shorts; plain saturated pure GREEN socks; black boots. Accessories like headbands, caps, earrings and wristbands stay as they are."
for id in kairo luna vega amara sora demba odin rex juno niko zeke amir; do
  f=${id}_ref_front.png; [ $id = luna ] && f=luna_ref_apose.png
  [ -f ${id}_ck_front.png ] || $PY make_ref.py $f ${id}_ck_front.png "$KIT" 1024x1536 &
  [ -f ${id}_ck_back.png ] || $PY make_ref.py ${id}_ref_back.png ${id}_ck_back.png "$KIT" 1024x1536 &
  while [ $(jobs -r | wc -l) -ge 4 ]; do sleep 2; done
done
wait
echo "CODEKIT DONE"
