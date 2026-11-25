#!/bin/sh
# Guard against upstream logo changes that would silently bring the original
# Tempus logo back. Run from the upstream source root, BEFORE copying the
# custom drawables in:
#
#   check-logo.sh <custom-res-dir>
#
# Fails when:
#   1. a drawable we generate no longer exists upstream (renamed or removed),
#      so our override would be dead and the new name would show the old logo
#   2. an upstream resource that contains the Tempus logo artwork is not
#      overridden by one of our files (new place showing the logo)
#   3. the logo artwork itself is gone from upstream (redesign), which makes
#      check 2 blind, so the fingerprint below needs updating
set -eu

custom="$1"
main=app/src/main/res
flavor=app/src/degoogled/res

# Outer circle of the Tempus record logo, present in every upstream logo file
fingerprint='M250,0c138.07,0 250,111.93'

errors=0
fail() {
    echo "check-logo: $1" >&2
    errors=$((errors + 1))
}

# 1. every generated file must override an existing upstream resource
for f in "$custom"/drawable/*.xml; do
    name="$(basename "$f")"
    if [ ! -e "$main/drawable/$name" ] && [ ! -e "$flavor/drawable/$name" ]; then
        fail "upstream has no drawable/$name anymore (renamed or removed?)"
    fi
done

# 2. every upstream file with the logo artwork must be overridden
found=0
matches="$(grep -rlF "$fingerprint" "$main" "$flavor" 2>/dev/null | sort -u)"
while IFS= read -r f; do
    [ -n "$f" ] || continue
    found=1
    rel="${f#"$main"/}"
    rel="${rel#"$flavor"/}"
    if [ ! -e "$custom/$rel" ]; then
        fail "upstream logo in $f is not replaced (expected $custom/$rel)"
    fi
done <<MATCHES
$matches
MATCHES

# 3. fingerprint must still match something, otherwise check 2 proves nothing
if [ "$found" -eq 0 ]; then
    fail "Tempus logo fingerprint not found upstream: logo was redesigned, review the drawables and update the fingerprint in scripts/check-logo.sh"
fi

if [ "$errors" -gt 0 ]; then
    echo "check-logo: $errors problem(s), see above" >&2
    exit 1
fi
echo "check-logo: all upstream logo resources are replaced"
