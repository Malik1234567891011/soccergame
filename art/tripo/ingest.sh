#!/bin/zsh
# Move finished Tripo exports from ~/Downloads and build each into a PANNA character.
cd ${0:A:h}/../..
setopt null_glob
for f in ~/Downloads/*_tripo.glb; do
  [ -f "$f.crdownload" ] && continue
  sz1=$(stat -f %z "$f"); sleep 2; [ "$(stat -f %z "$f")" != "$sz1" ] && continue
  mv "$f" art/tripo/
done
for g in art/tripo/*_tripo.glb; do
  id=$(basename $g _tripo.glb)
  bin=Panna/Resources/Characters/$id.bin
  if [ ! -f art/tripo/.done_$id ] || [ $g -nt art/tripo/.done_$id ]; then
    /Applications/Blender.app/Contents/MacOS/Blender -b -P art/blender/tripo_char.py -- --mesh $PWD/$g --name $id --tris 20000 --preview 2>&1 | grep -E "TRIPO exported|Traceback" && touch art/tripo/.done_$id
  fi
done
