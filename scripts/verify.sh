#!/usr/bin/env bash
# Apply the patches to the pinned release, then run the busy-slots unit tests, upstream's
# getSchedule suite (to catch regressions with the flag off) and a type-check of apps/web.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="$root/src"

"$root/scripts/fetch.sh" "$src"
cp "$root/tests/busySlots.test.ts" "$src/apps/web/test/lib/getSchedule/busySlots.test.ts"

cd "$src"
corepack enable
# Same install settings as upstream's CI (.github/actions/yarn-install).
YARN_ENABLE_IMMUTABLE_INSTALLS=false YARN_ENABLE_GLOBAL_CACHE=false YARN_NM_MODE=hardlinks-local HUSKY=0 \
  yarn install --inline-builds
yarn prisma generate

TZ=UTC yarn vitest run apps/web/test/lib/getSchedule apps/web/test/lib/getSchedule.test.ts

# Upstream's own type-check task for the web app (it builds @calcom/trpc first).
NODE_OPTIONS=--max-old-space-size=12288 yarn turbo run type-check:ci --filter=@calcom/web
