#!/bin/sh
set -eu
out=$(mktemp)
trap 'rm -f "$out"' EXIT HUP INT TERM
secret='DO_NOT_LOG_DB_CREDENTIAL'
url="postgresql://svc:$secret@db.example/app"
if env \
  LIB_CORE_ROOT=/nonexistent/lib-core \
  ORM_CORE_ROOT=/nonexistent/orm-core \
  TARGET_DATABASE_URL="$url" \
  SHADOW_DATABASE_URL="$url" \
  VECTOR_DB_PROFILE=postgresql \
  VECTOR_MIGRATION_ACTION=plan \
  sh scripts/vector-migrations.sh >"$out" 2>&1; then
  echo "identical shadow and target databases were accepted" >&2
  exit 1
fi
grep -Fq "target and shadow database URLs must be distinct" "$out"
if grep -Fq "$secret" "$out"; then
  echo "database credential appeared in rejection diagnostic" >&2
  exit 1
fi
echo "vector migration distinct database preflight passed"
