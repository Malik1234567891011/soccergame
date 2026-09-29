#!/bin/zsh
cd ${0:A:h}/../ai3d
while IFS=$'\t' read id desc; do
  [ -f ${id}_ref_front.png ] && continue
  python3 ../../scripts/genimage.py ${id}_ref_front.png "Full-body character model sheet for a 3D modeller of an ORIGINAL anime street footballer. FRONT view, standing straight in a relaxed A-pose with arms angled about 30 degrees away from the body and hands open, feet shoulder-width apart, the whole body from the top of the hair down to the boots fully visible with generous empty margin (figure occupies about 70% of the image height), plain flat light grey background, no ground shadow. Character: $desc. Outfit (exactly, no variations): a plain short-sleeved football jersey in flat saturated pure RED with a bright YELLOW V-collar and yellow sleeve cuffs, no logos, no numbers, no stripes; plain saturated pure BLUE football shorts; plain saturated pure GREEN knee-high football socks; black football boots. Style: premium cel-shaded anime model sheet in the style of Blue Lock and Genshin Impact, expressive handsome anime face, crisp clean line art, even flat lighting. No text." 1024x1536 high &
  while [ $(jobs -r | wc -l) -ge 4 ]; do sleep 2; done
done < ../roster/looks.tsv
wait
echo FRONTS DONE
