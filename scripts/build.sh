#!/usr/bin/env bash
# Build the patched image with upstream's own Dockerfile and build arguments, the way
# calcom/cal.com's release workflow does: a throwaway Postgres for the Next.js build, and
# NEXT_PUBLIC_WEBAPP_URL baked as localhost (start.sh swaps in the real URL at runtime).
#
#   IMAGE=ghcr.io/<owner>/cal-patches scripts/build.sh
#
# Prints the built reference (image:tag) on the last line.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image="${IMAGE:-ghcr.io/robbeverhelst/cal-patches}"
tag="$("$root/scripts/image-tag.sh")"
src="$root/src"
db=cal-patches-build-db

"$root/scripts/fetch.sh" "$src" >&2

docker rm -f "$db" >/dev/null 2>&1 || true
trap 'docker rm -f "$db" >/dev/null 2>&1 || true' EXIT
docker run -d --name "$db" -p 5432:5432 \
  -e POSTGRES_USER=cal -e POSTGRES_PASSWORD=cal -e POSTGRES_DB=cal postgres:16 >&2
until docker exec "$db" pg_isready -U cal >/dev/null 2>&1; do sleep 1; done

docker build --network host \
  --build-arg NEXT_PUBLIC_WEBAPP_URL=http://localhost:3000 \
  --build-arg NEXT_PUBLIC_API_V2_URL=http://localhost:5555/api/v2 \
  --build-arg NEXT_PUBLIC_LICENSE_CONSENT=agree \
  --build-arg DATABASE_URL=postgresql://cal:cal@localhost:5432/cal \
  --build-arg DATABASE_DIRECT_URL=postgresql://cal:cal@localhost:5432/cal \
  -t "$image:$tag" "$src" >&2

echo "$image:$tag"
