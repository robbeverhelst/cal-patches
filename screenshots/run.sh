#!/usr/bin/env bash
# Boot an image against a throwaway Postgres, seed dummy data, and capture the booker.
#   screenshots/run.sh <image> <label> <CAL_SHOW_BUSY_SLOTS value> <expectBusy 0|1> <outDir>
set -euo pipefail

image="$1" label="$2" flag="$3" expect_busy="$4" out="$5"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
net=cal-shots db=cal-shots-db app=cal-shots-app

# Next Tuesday at least five days out is booked, the Wednesday after it is blocked: same week, any month.
for i in $(seq 5 11); do
  booked="$(TZ=Europe/Brussels date -d "+$i days" +%F)"
  [ "$(date -d "$booked" +%u)" = 2 ] && break
done
blocked="$(date -d "$booked +1 day" +%F)"

cleanup() { docker rm -f "$app" "$db" >/dev/null 2>&1 || true; }
cleanup
trap cleanup EXIT
docker network inspect "$net" >/dev/null 2>&1 || docker network create "$net" >/dev/null

docker run -d --name "$db" --network "$net" \
  -e POSTGRES_USER=cal -e POSTGRES_PASSWORD=cal -e POSTGRES_DB=cal postgres:16 >/dev/null
until docker exec "$db" pg_isready -U cal >/dev/null 2>&1; do sleep 1; done

# Throwaway secrets for a throwaway instance.
docker run -d --name "$app" --network "$net" -p 3000:3000 \
  -e DATABASE_URL=postgresql://cal:cal@"$db":5432/cal \
  -e DATABASE_DIRECT_URL=postgresql://cal:cal@"$db":5432/cal \
  -e DATABASE_HOST="$db":5432 \
  -e NEXTAUTH_SECRET=screenshot-run-only \
  -e CALENDSO_ENCRYPTION_KEY=screenshotrunonlyscreenshotrun00 \
  -e NEXT_PUBLIC_WEBAPP_URL=http://localhost:3000 \
  -e NEXTAUTH_URL=http://localhost:3000/api/auth \
  -e CAL_SHOW_BUSY_SLOTS="$flag" \
  "$image" >/dev/null

echo "waiting for $label to start (migrations run first)"
for _ in $(seq 1 120); do
  code="$(curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/auth/login || true)"
  [ "$code" = 200 ] || [ "$code" = 307 ] && break
  sleep 5
done
if ! { [ "$code" = 200 ] || [ "$code" = 307 ]; }; then
  docker logs --tail 200 "$app"
  echo "::error::$label did not start" >&2
  exit 1
fi

echo "$label: CAL_SHOW_BUSY_SLOTS=$(docker exec "$app" printenv CAL_SHOW_BUSY_SLOTS || true)"
docker exec -i "$db" psql -q -U cal -d cal -v booked="$booked" -v blocked="$blocked" <"$here/seed.sql"
node "$here/capture.mjs" "$label" "$out" "$booked" "$blocked" "$expect_busy"
