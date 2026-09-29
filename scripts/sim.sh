#!/bin/zsh
# Build, install and launch PANNA on the simulator. Extra args become env vars, e.g.:
#   scripts/sim.sh PANNA_QUICK=1 PANNA_BOTS=1
# Screenshot: scripts/sim.sh shot name.png
SIM=${PANNA_SIM:-6FB9A6DC-8EE5-44E1-80BA-06974D8950F9}
ROOT=${0:A:h:h}
OUT=${SHOTS:-/tmp/panna-shots}
mkdir -p $OUT
if [[ "$1" == "shot" ]]; then
  xcrun simctl io $SIM screenshot $OUT/raw.png >/dev/null 2>&1
  sips -r 270 $OUT/raw.png --out $OUT/$2 >/dev/null 2>&1
  sips -Z 1100 $OUT/$2 >/dev/null 2>&1
  echo $OUT/$2
  exit 0
fi
cd $ROOT
xcodegen generate >/dev/null
xcodebuild -project Panna.xcodeproj -scheme Panna -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath build/DD build 2>&1 | grep -E "error:|BUILD FAILED" && exit 1
xcrun simctl boot $SIM 2>/dev/null
xcrun simctl terminate $SIM com.malik.panna 2>/dev/null
xcrun simctl install $SIM build/DD/Build/Products/Debug-iphonesimulator/Panna.app
envs=("SIMCTL_CHILD_PANNA_MUTE=1")
for kv in "$@"; do envs+=("SIMCTL_CHILD_$kv"); done
env $envs xcrun simctl launch $SIM com.malik.panna
