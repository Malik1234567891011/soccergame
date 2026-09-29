#!/bin/zsh
cd ${0:A:h}
until grep -q "BATCH DONE" /tmp/batch_prospects.log 2>/dev/null; do sleep 10; done
for f in l*_ref_front.png; do
  id=${f%_ref_front.png}
  if [ ! -f ../../Panna/Resources/Characters/$id.bin ]; then
    echo "=== $id $(date +%T)"
    ./build_character.sh $id "" || echo "FAILED $id"
  fi
  # Portrait thumbnail: head-and-shoulders crop of the front sheet.
  sips -c 440 440 --cropOffset 170 292 $f --out /tmp/crop_$id.png >/dev/null 2>&1
  sips -s format jpeg -s formatOptions 82 -Z 220 /tmp/crop_$id.png --out ../../Panna/Resources/Portraits/look_$id.jpg >/dev/null 2>&1
done
echo "ROSTER DONE $(date +%T)"
