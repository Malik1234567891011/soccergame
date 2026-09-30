#!/bin/zsh
# Front A-pose code-kit model sheet (+ gacha card) for a look: gen_front.sh <id> "<character description>" [nocard]
set -e
cd ${0:A:h}
ID=$1; DESC=$2
PY=/private/tmp/ai3dvenv/bin/python
[ -f ${ID}_ref_front.png ] && mv ${ID}_ref_front.png old/${ID}_ref_front.$(date +%s).png
FRONT="Draw this NEW anime footballer character (replace the reference person entirely: new face, hairstyle, build and skin tone exactly as described): $DESC. Keep only the pose, framing and art style of the reference image: full-body FRONT view model sheet for a 3D modeller, relaxed A-pose with arms angled about 30 degrees away from the body and hands open, feet shoulder-width apart, whole body from hair to boots visible with generous margin (figure about 70% of image height), plain flat light grey background, no ground shadow. Outfit must be EXACTLY: plain solid red short-sleeve football jersey with a yellow V collar and yellow sleeve cuffs, solid blue shorts, solid green socks, black football boots, no logos, no numbers. Highly detailed, distinctive, instantly recognisable face and hair: a faithful semi-realistic anime likeness (accurate face shape, nose, eyes, jaw, skin tone, hairline and hairstyle), premium gacha / Blue Lock anime cel shading with clean line art, same rendering quality as the reference. No text."
$PY make_ref.py ${STYLE:-luna_ck_front.png} ${ID}_ref_front.png "$FRONT" 1024x1536
if [ "$3" != "nocard" ]; then
$PY make_ref.py ${ID}_ref_front.png ../looks/${ID}_card.png "Dramatic gacha trading-card illustration of this exact same character (same face, hair, skin, same red/yellow/blue football kit), dynamic heroic football pose mid-action with a ball, intense expression, glowing personal aura and energy streaks in their signature colour, stadium lights at night, Blue Lock anime key-visual style, vertical composition, character fills the frame. No text, no logos." 1024x1536
fi
echo "DONE $ID"
