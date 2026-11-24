#!/bin/sh
# zipalign + apksigner every unsigned release APK into $1.
# Secrets are read from /run/secrets (BuildKit secret mounts), never from layers.
set -eu

out="$1"
bt="$ANDROID_HOME/build-tools/$(cat /opt/build-tools-version)"
version="$(sed 's/^v//' /src/.tempus-tag)"
apk_dir=/src/app/build/outputs/apk/degoogled/release

set -- --ks /run/secrets/keystore --ks-pass file:/run/secrets/ks_pass
if [ -s /run/secrets/key_pass ]; then
    set -- "$@" --key-pass file:/run/secrets/key_pass
fi
if [ -n "${KEY_ALIAS:-}" ]; then
    set -- "$@" --ks-key-alias "$KEY_ALIAS"
fi

mkdir -p "$out"
found=0
for apk in "$apk_dir"/*-release-unsigned.apk; do
    [ -e "$apk" ] || continue
    found=1
    # app-degoogled-arm64-v8a-release-unsigned.apk -> arm64-v8a
    abi="$(basename "$apk" -release-unsigned.apk)"
    abi="${abi#app-degoogled-}"
    dest="$out/tempus-degoogled-$version-$abi.apk"

    # -P 16: 16 KB page alignment for native libs (Android 15+)
    "$bt/zipalign" -P 16 -f 4 "$apk" /tmp/aligned.apk
    "$bt/apksigner" sign "$@" --out "$dest" /tmp/aligned.apk
    "$bt/apksigner" verify "$dest"
    rm -f /tmp/aligned.apk "$dest.idsig"
    echo "Signed: $(basename "$dest")"
done

if [ "$found" -eq 0 ]; then
    echo "No unsigned APKs found in $apk_dir" >&2
    exit 1
fi

# Certificate info is public anyway (it is inside every APK); kept for release notes.
"$bt/apksigner" verify --print-certs "$out/tempus-degoogled-$version-universal.apk" \
    | grep -E 'DN:|SHA-256' > "$out/signing-cert.txt"
cat "$out/signing-cert.txt"
(cd "$out" && sha256sum ./*.apk > SHA256SUMS)
