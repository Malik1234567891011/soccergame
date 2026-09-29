#!/bin/zsh
# Build + render every character (2 kits, face / idle / run) into contact sheets, copied to $1 (default /tmp/panna-roster).
SIM=${PANNA_SIM:-6FB9A6DC-8EE5-44E1-80BA-06974D8950F9}
OUT=${1:-/tmp/panna-roster}
ROOT=${0:A:h:h}
D=$(xcrun simctl get_app_container $SIM com.malik.panna data 2>/dev/null)/Documents/poses
rm -rf $D
$ROOT/scripts/sim.sh PANNA_POSESHEET=${PANNA_POSESHEET:-roster} || exit 1
D=$(xcrun simctl get_app_container $SIM com.malik.panna data)/Documents/poses
for i in $(seq 1 100); do [ -f $D/roster_k1_3.jpg ] && break; sleep 3; done
sleep 2
mkdir -p $OUT && cp $D/*.jpg $OUT/ && echo "sheets in $OUT"
