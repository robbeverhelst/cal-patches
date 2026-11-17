#!/usr/bin/env bash
# Print the image tag for the current upstream version and patches: <version>-p<sha256(patches)[:12]>.
# Same inputs, same tag, so a rebuild of an unchanged patch set pushes nothing new.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=upstream.env
source "$root/upstream.env"

echo "${CAL_VERSION}-p$(cat "$root"/patches/*.patch | sha256sum | cut -c1-12)"
