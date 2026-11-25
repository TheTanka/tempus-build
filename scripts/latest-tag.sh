#!/bin/sh
# Print the newest stable upstream Tempus tag (X.Y.Z with or without a leading v,
# skips -dev and other prereleases). Used by build.sh for local builds; the
# GitHub workflow asks the GitHub API for the release marked "Latest" instead.
# Uses git, not the GitHub API, so it never hits API rate limits.
set -eu

repo="${1:-https://github.com/eddyizm/tempus.git}"

# Sort on the version without "v", so "5.0.0" and "v4.32.0" compare correctly.
tag="$(git ls-remote --refs --tags "$repo" \
    | sed 's|.*refs/tags/||' \
    | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' \
    | awk '{ v = $0; sub(/^v/, "", v); print v "\t" $0 }' \
    | sort -V -k1,1 \
    | tail -n 1 \
    | cut -f2)"

if [ -z "$tag" ]; then
    echo "latest-tag: no stable tag found in $repo" >&2
    exit 1
fi

echo "$tag"
