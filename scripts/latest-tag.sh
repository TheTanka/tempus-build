#!/bin/sh
# Print the newest stable upstream Tempus tag (vX.Y.Z, skips -dev prereleases).
# Uses git, not the GitHub API, so it never hits API rate limits.
set -eu

repo="${1:-https://github.com/eddyizm/tempus.git}"

tag="$(git ls-remote --refs --tags "$repo" \
    | sed 's|.*refs/tags/||' \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
    | sort -V \
    | tail -n 1)"

if [ -z "$tag" ]; then
    echo "latest-tag: no stable tag found in $repo" >&2
    exit 1
fi

echo "$tag"
