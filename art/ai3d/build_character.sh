#!/bin/zsh
# Full painted-character pipeline for one Prospect: art/ai3d/build_character.sh <id> "<description for the model sheet>"
# 1) front A-pose model sheet from the gacha illustration  2) back/left/right views  3) Hunyuan3D-2 shape  4) Blender bake+rig+export
set -e
cd ${0:A:h}
ID=$1; DESC=$2
PY=/private/tmp/ai3dvenv/bin/python
B=/Applications/Blender.app/Contents/MacOS/Blender
SHEET="Full-body character model sheet of this exact same character for a 3D modeller: FRONT view, standing straight in a relaxed A-pose with arms angled about 30 degrees away from the body and hands open, feet shoulder-width apart, the whole body from the top of the hair down to the football boots fully visible with generous empty margin around it (figure occupies about 70% of the image height), plain flat light grey background, no ground shadow. Keep exactly the same face, hair, skin tone and outfit. $DESC Clean cel-shaded anime model-sheet style, even lighting. No text."
[ -f ${ID}_ref_front.png ] || $PY make_ref.py ../prospects/$ID.png ${ID}_ref_front.png "$SHEET" 1024x1536
BASE="Character model sheet of the exact same anime character, identical outfit, colours, hair and body proportions, same light A-pose, same scale and framing, full body centred with the same padding, plain light grey background, cel-shaded anime style with clean line art. No text."
[ -f ${ID}_ref_back.png ] || $PY make_ref.py ${ID}_ref_front.png ${ID}_ref_back.png "$BASE View: seen from DIRECTLY BEHIND (back view): the back of the head and hair, the back of the jersey, shorts, calves and boot heels." 1024x1536 &
[ -f ${ID}_ref_left.png ] || $PY make_ref.py ${ID}_ref_front.png ${ID}_ref_left.png "$BASE View: strict SIDE PROFILE seen from the character's LEFT side (the character faces the right edge of the image), arms slightly away from the body." 1024x1536 &
[ -f ${ID}_ref_right.png ] || $PY make_ref.py ${ID}_ref_front.png ${ID}_ref_right.png "$BASE View: strict SIDE PROFILE seen from the character's RIGHT side (the character faces the left edge of the image), arms slightly away from the body." 1024x1536 &
[ -f ${ID}_shape.glb ] || $PY run_hy2_shape.py ${ID}_ref_front.png ${ID}_shape.glb
wait
$B -b -P ../blender/unique.py -- --mesh $PWD/${ID}_shape.glb --front $PWD/${ID}_ref_front.png --back $PWD/${ID}_ref_back.png \
   --left $PWD/${ID}_ref_left.png --right $PWD/${ID}_ref_right.png --name $ID --preview 2>&1 | grep -E "UNIQUE|Error|Traceback"
ffmpeg -loglevel error -y -i ${ID}_proj_front.png -i ${ID}_proj_34.png -i ${ID}_proj_side.png -i ${ID}_proj_back.png -filter_complex "[0][1][2][3]hstack=inputs=4,scale=1400:-1" ${ID}_sheet.png
echo "DONE $ID"
