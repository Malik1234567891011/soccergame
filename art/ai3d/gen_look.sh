#!/bin/zsh
# Redesign an avatar look as a new character: art/ai3d/gen_look.sh <id> "<character description>"
# Uses an existing code-kit model sheet only as a pose/framing/style guide.
set -e
cd ${0:A:h}
ID=$1; DESC=$2
PY=/private/tmp/ai3dvenv/bin/python
for f in ${ID}_ref_front.png ${ID}_ref_back.png ${ID}_ref_left.png ${ID}_ref_right.png ${ID}_shape.glb; do [ -f $f ] && mv $f old/ ; done
FRONT="Draw a COMPLETELY DIFFERENT, NEW anime footballer character (new face, new hairstyle, new build, new skin tone as described): $DESC. Keep only the pose, framing and art style of the reference: full-body FRONT view model sheet for a 3D modeller, relaxed A-pose with arms angled about 30 degrees away from the body and hands open, feet shoulder-width apart, whole body from hair to boots visible with generous margin (figure about 70% of image height), plain flat light grey background, no ground shadow. Outfit must be EXACTLY: plain solid red short-sleeve football jersey with a yellow V collar and yellow sleeve cuffs, solid blue shorts, solid green socks, black football boots, no logos, no numbers, no accessories on the jersey. Strong, distinctive silhouette and personality, Blue Lock / Inazuma Eleven quality anime cel shading with clean line art. No text."
$PY make_ref.py old/l01_ref_front.png ${ID}_ref_front.png "$FRONT" 1024x1536
BASE="Character model sheet of the exact same anime character, identical outfit, colours, hair and body proportions, same light A-pose, same scale and framing, full body centred with the same padding, plain light grey background, cel-shaded anime style with clean line art. No text."
$PY make_ref.py ${ID}_ref_front.png ${ID}_ref_back.png "$BASE View: seen from DIRECTLY BEHIND (back view): the back of the head and hair, the back of the jersey, shorts, calves and boot heels." 1024x1536 &
$PY make_ref.py ${ID}_ref_front.png ${ID}_ref_left.png "$BASE View: strict SIDE PROFILE seen from the character's LEFT side (the character faces the right edge of the image), arms slightly away from the body." 1024x1536 &
$PY make_ref.py ${ID}_ref_front.png ${ID}_ref_right.png "$BASE View: strict SIDE PROFILE seen from the character's RIGHT side (the character faces the left edge of the image), arms slightly away from the body." 1024x1536 &
$PY make_ref.py ${ID}_ref_front.png ../looks/${ID}_card.png "Dramatic gacha trading-card illustration of this exact same character (same face, hair, skin, same red/yellow/blue football kit), dynamic heroic football pose mid-action with a ball, intense expression, glowing personal aura and energy streaks in their signature colour, stadium lights at night, Blue Lock anime key-visual style, vertical composition, character fills the frame. No text, no logos." 1024x1536 &
$PY run_hy2_shape.py ${ID}_ref_front.png ${ID}_shape.glb
wait
echo "DONE $ID"
