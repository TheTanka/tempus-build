#!/usr/bin/env bash
# Build + sign Tempus (degoogled, release) with the custom icon from logo.svg.
#
# Required:
#   KEYSTORE        path to your keystore (.p12/.jks)
#   KS_PASS_FILE    file containing the keystore password   (or KS_PASS env var)
# Optional:
#   KEY_PASS_FILE   file containing the key password, if it differs (or KEY_PASS)
#   KEY_ALIAS       key alias, only needed if the keystore holds several keys
#   TEMPUS_TAG      upstream tag to build, e.g. v4.32.0 (default: latest stable)
#   Any extra args are passed to docker build, e.g.
#     --build-arg ICON_BG=#1e1e2e      icon background colour
#     --build-arg ICON_RADIUS=28       logo size inside the safe zone (max 33)
#     --build-arg APP_ID_SUFFIX=.foo   applicationId suffix
#
# Output: ./out/ (signed APKs, SHA256SUMS, signing-cert.txt, icon-preview.png)
set -euo pipefail
cd "$(dirname "$0")"

: "${KEYSTORE:?set KEYSTORE=/path/to/keystore}"

secrets=(--secret "id=keystore,src=${KEYSTORE}")

if [[ -n "${KS_PASS_FILE:-}" ]]; then
    secrets+=(--secret "id=ks_pass,src=${KS_PASS_FILE}")
elif [[ -n "${KS_PASS:-}" ]]; then
    secrets+=(--secret "id=ks_pass,env=KS_PASS")
else
    echo "set KS_PASS_FILE or KS_PASS" >&2
    exit 1
fi

if [[ -n "${KEY_PASS_FILE:-}" ]]; then
    secrets+=(--secret "id=key_pass,src=${KEY_PASS_FILE}")
elif [[ -n "${KEY_PASS:-}" ]]; then
    secrets+=(--secret "id=key_pass,env=KEY_PASS")
fi

tag="${TEMPUS_TAG:-$(scripts/latest-tag.sh)}"
echo "Upstream tag: ${tag}"

rm -rf out
# --no-cache-filter sign: always re-sign, BuildKit does not track secret changes.
docker build \
    "${secrets[@]}" \
    --build-arg "TEMPUS_TAG=${tag}" \
    --build-arg "KEY_ALIAS=${KEY_ALIAS:-}" \
    --no-cache-filter sign \
    --output type=local,dest=out \
    "$@" \
    .

ls -l out
