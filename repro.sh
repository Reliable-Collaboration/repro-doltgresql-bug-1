#!/bin/sh
# Runs repro.sql in a throwaway container and prints everything the server answers.
#
#   ./repro.sh            DoltgreSQL 1.3.1, where the bug shows (exits 1)
#   ./repro.sh postgres   PostgreSQL 18.6, the expected behavior (exits 0)
#
# Another DoltgreSQL image: DOLTGRESQL_IMAGE=dolthub/doltgresql:latest ./repro.sh
set -eu
cd "$(dirname "$0")"

ENGINE="${1:-doltgresql}"
case "$ENGINE" in
  doltgresql)
    IMAGE="${DOLTGRESQL_IMAGE:-dolthub/doltgresql:1.3.1@sha256:6c85cb1f35beabf47f094336a420255130b841b1645f36d79ef046276af36851}"
    PASSWORD_VARIABLE=DOLTGRES_PASSWORD ;;
  postgres)
    IMAGE="${POSTGRES_IMAGE:-postgres:18.6-bookworm@sha256:1c59e2c3c818eaa0f0628f695b36e7c9e362d6b219b36a54a32df645cbd7e1af}"
    PASSWORD_VARIABLE=POSTGRES_PASSWORD ;;
  *)
    echo "usage: $0 [doltgresql|postgres]" >&2
    exit 2 ;;
esac

NAME="repro-doltgresql-bug-1-$ENGINE"
docker rm -f "$NAME" >/dev/null 2>&1 || true
trap 'docker rm -f "$NAME" >/dev/null 2>&1 || true' EXIT

echo "Starting $IMAGE"
docker run -d --name "$NAME" -e "$PASSWORD_VARIABLE=password" "$IMAGE" >/dev/null

# Wait until the server answers over TCP twice in a row.
ok=0
tries=0
while [ "$ok" -lt 2 ]; do
  if docker exec -e PGPASSWORD=password "$NAME" psql -X -h 127.0.0.1 -U postgres -d postgres -tAc 'SELECT 1' >/dev/null 2>&1; then
    ok=$((ok + 1))
  else
    ok=0
  fi
  tries=$((tries + 1))
  if [ "$tries" -gt 120 ]; then
    echo "The server did not start. Its log:" >&2
    docker logs "$NAME" >&2
    exit 2
  fi
  sleep 1
done

docker cp repro.sql "$NAME:/tmp/repro.sql" >/dev/null 2>&1 || { echo "Could not copy repro.sql into $NAME" >&2; exit 2; }
echo "Running repro.sql"
echo

# -t gives psql a terminal, so each error is printed right after the statement that caused it.
OUTPUT=$(docker exec -t -e PGPASSWORD=password "$NAME" \
  psql -X -P pager=off -h 127.0.0.1 -U postgres -d postgres --echo-all -f /tmp/repro.sql | tr -d '\r')
printf '%s\n\n' "$OUTPUT"

ERRORS=$(printf '%s\n' "$OUTPUT" | grep -c -E '(ERROR|FATAL):|psql: error' || true)
if [ "$ERRORS" -gt 0 ]; then
  echo "Result: the server answered with $ERRORS error(s)."
  exit 1
fi
echo "Result: no errors."
