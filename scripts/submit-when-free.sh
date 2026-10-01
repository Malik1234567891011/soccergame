#!/bin/zsh
# Polls App Store Connect and submits build $1 for beta review as soon as the previous build's review completes.
cd ${0:A:h}/..
for i in $(seq 1 300); do
  o=$(node scripts/asc.mjs POST "/v1/betaAppReviewSubmissions" "{\"data\":{\"type\":\"betaAppReviewSubmissions\",\"relationships\":{\"build\":{\"data\":{\"type\":\"builds\",\"id\":\"$1\"}}}}}")
  if echo "$o" | grep -q '^201'; then echo "$(date) submitted $1"; exit 0; fi
  if echo "$o" | grep -q 'already been submitted\|ENTITY_ERROR.RELATIONSHIP.INVALID'; then echo "$(date) $o" | head -3; exit 0; fi
  sleep 600
done
