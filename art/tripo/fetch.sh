#!/bin/zsh
# fetch.sh <id> '<signed tripo_pbr_model meshopt URL from the studio page>' → art/tripo/<id>_tripo.glb (decoded)
# (Chrome blocks repeated Studio exports; the viewer's own model URL is the same asset.)
cd ${0:A:h}
curl -sS -o $1_mo.glb "$2" && npx -y @gltf-transform/cli@4 copy $1_mo.glb $1_tripo.glb >/dev/null 2>&1 && rm $1_mo.glb && ls -la $1_tripo.glb | awk '{print $5, $9}'
