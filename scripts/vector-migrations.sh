#!/bin/sh
set -eu

if [ "$#" -ne 0 ]; then
  echo "vector-migrations.sh accepts environment variables only; command-line arguments are rejected" >&2
  exit 64
fi

: "${LIB_CORE_ROOT:?set LIB_CORE_ROOT to the pinned fanwaave-lib-core checkout}"
: "${ORM_CORE_ROOT:?set ORM_CORE_ROOT to the pinned fanwaave-orm-core checkout}"
: "${TARGET_DATABASE_URL:?set TARGET_DATABASE_URL for declarative-postgres-migrate}"
: "${SHADOW_DATABASE_URL:?set SHADOW_DATABASE_URL to a CREATEDB-capable scratch server}"
: "${VECTOR_DB_PROFILE:?set VECTOR_DB_PROFILE to postgresql, neon, or supabase}"
: "${VECTOR_MIGRATION_ACTION:?set VECTOR_MIGRATION_ACTION to plan, verify, or apply}"

DPM_BIN=${DPM_BIN:-dpm}
PSQL_BIN=${PSQL_BIN:-psql}
SCRIPT_DIR=$(unset CDPATH; cd -- "$(dirname -- "$0")" && pwd)
INFRA_ROOT=$(dirname -- "$SCRIPT_DIR")
MANIFEST_PATH=${MANIFEST_PATH:-$INFRA_ROOT/database/vector-migrations.json}

case "$VECTOR_DB_PROFILE" in
  postgresql | neon | supabase) ;;
  *)
    echo "unsupported VECTOR_DB_PROFILE: $VECTOR_DB_PROFILE" >&2
    exit 64
    ;;
esac

case "$VECTOR_MIGRATION_ACTION" in
  plan | verify | apply) ;;
  *)
    echo "unsupported VECTOR_MIGRATION_ACTION: $VECTOR_MIGRATION_ACTION" >&2
    exit 64
    ;;
esac

command -v node >/dev/null
command -v "$DPM_BIN" >/dev/null

SOURCE_DATABASE_URL="$LIB_CORE_ROOT/embedding-contract/sql/postgres/desired.sql"
export SOURCE_DATABASE_URL TARGET_DATABASE_URL SHADOW_DATABASE_URL

expected_lib_revision=$(node -e 'const fs=require("fs"); const m=JSON.parse(fs.readFileSync(process.argv[1], "utf8")); process.stdout.write(m.source.revision)' "$MANIFEST_PATH")
expected_orm_revision=$(node -e 'const fs=require("fs"); const m=JSON.parse(fs.readFileSync(process.argv[1], "utf8")); process.stdout.write(m.runtimeMirror.revision)' "$MANIFEST_PATH")
actual_lib_revision=$(git -C "$LIB_CORE_ROOT" rev-parse HEAD)
actual_orm_revision=$(git -C "$ORM_CORE_ROOT" rev-parse HEAD)

if [ "$actual_lib_revision" != "$expected_lib_revision" ]; then
  echo "lib-core revision mismatch: expected $expected_lib_revision, got $actual_lib_revision" >&2
  exit 65
fi
if [ "$actual_orm_revision" != "$expected_orm_revision" ]; then
  echo "orm-core revision mismatch: expected $expected_orm_revision, got $actual_orm_revision" >&2
  exit 65
fi

LIB_CORE_ROOT="$LIB_CORE_ROOT" node "$ORM_CORE_ROOT/scripts/verify-embedding-contract.mjs"

case "$VECTOR_MIGRATION_ACTION" in
  plan)
    "$DPM_BIN" diff
    ;;
  verify)
    "$DPM_BIN" verify
    ;;
  apply)
    : "${REVIEWED_PLAN_CHECKSUM:?set the checksum emitted by the reviewed dpm diff}"
    : "${VECTOR_PSQL_SERVICE:?set a libpq service that addresses the same target database}"
    command -v "$PSQL_BIN" >/dev/null

    "$DPM_BIN" verify
    "$DPM_BIN" apply --yes --require-plan-checksum "$REVIEWED_PLAN_CHECKSUM"

    PGSERVICE="$VECTOR_PSQL_SERVICE" "$PSQL_BIN" -X --set ON_ERROR_STOP=1 \
      --file "$LIB_CORE_ROOT/embedding-contract/sql/postgres/preflight.sql"
    PGSERVICE="$VECTOR_PSQL_SERVICE" "$PSQL_BIN" -X --set ON_ERROR_STOP=1 \
      --file "$LIB_CORE_ROOT/embedding-contract/sql/postgres/reconcile-index.sql"

    if [ "$VECTOR_DB_PROFILE" = "supabase" ]; then
      PGSERVICE="$VECTOR_PSQL_SERVICE" "$PSQL_BIN" -X --set ON_ERROR_STOP=1 \
        --file "$LIB_CORE_ROOT/embedding-contract/sql/supabase/private-adapter.sql"
      PGSERVICE="$VECTOR_PSQL_SERVICE" "$PSQL_BIN" -X --set ON_ERROR_STOP=1 \
        --file "$LIB_CORE_ROOT/embedding-contract/sql/supabase/verify-private.sql"
    fi

    "$DPM_BIN" diff --fail-on-diff
    ;;
esac
