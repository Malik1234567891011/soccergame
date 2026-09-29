#!/bin/zsh
cd ${0:A:h}
for id in vega amara sora demba odin rex juno niko zeke amir; do
  if [ -f ../../Panna/Resources/Characters/$id.bin ]; then echo "skip $id"; continue; fi
  echo "=== $id $(date +%T)"
  ./build_character.sh $id "" || echo "FAILED $id"
done
echo "BATCH DONE $(date +%T)"
