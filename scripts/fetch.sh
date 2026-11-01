#!/usr/bin/env bash
# Clone the pinned Cal.com release into a directory and apply every patch in patches/.
# Exits non-zero, naming the patch, when one does not apply cleanly.
#
#   scripts/fetch.sh [dest]    (default: ./src)
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=upstream.env
source "$root/upstream.env"
dest="${1:-$root/src}"

rm -rf "$dest"
git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$CAL_VERSION" https://github.com/calcom/cal.com "$dest"

for patch in "$root"/patches/*.patch; do
  name="$(basename "$patch")"
  if ! git -C "$dest" apply --check "$patch"; then
    echo "::error::$name does not apply to calcom/cal.com $CAL_VERSION. See 'Refreshing a patch' in the README." >&2
    exit 1
  fi
  git -C "$dest" apply "$patch"
  echo "applied $name to calcom/cal.com $CAL_VERSION"
done
