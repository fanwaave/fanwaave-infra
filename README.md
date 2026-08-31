# fanwaave-infra

Cloudflare Workers and Kubernetes manifests for `fanwaave`. Cluster source of truth remains github.com/oresoftware/k8s-cluster.

## Vector database migrations

This repository owns deployment orchestration for Fanwaave's embedding schema.
The product contract and declarative PostgreSQL desired state live in
`fanwaave-lib-core`; `fanwaave-orm-core` is a byte-locked runtime mirror.
Neither application startup nor a shared ORESoftware repository may generate
or apply Fanwaave SQL.

`database/vector-migrations.json` pins the reviewed lib-core, orm-core, and
declarative-migrations revisions. `scripts/vector-migrations.sh` rejects
command-line arguments and reads connection material from the environment:

```text
LIB_CORE_ROOT=/checkout/fanwaave-lib-core
ORM_CORE_ROOT=/checkout/fanwaave-orm-core
TARGET_DATABASE_URL=<secret PostgreSQL-compatible connection URL>
SHADOW_DATABASE_URL=<secret CREATEDB-capable scratch-server URL>
VECTOR_DB_PROFILE=postgresql|neon|supabase
VECTOR_MIGRATION_ACTION=plan|verify|apply
DPM_BIN=/reviewed/path/to/dpm
```

Run `plan` first and review the SQL plus the checksum printed by DPM. Run
`verify` to rehearse the migration against disposable shadow databases. Only
the protected deployment job runs `apply`, with
`REVIEWED_PLAN_CHECKSUM=<reviewed checksum>` and
`VECTOR_PSQL_SERVICE=<libpq service for the same target>`. The service indirection
keeps database credentials out of process arguments.

The apply path fails closed on source-lock drift, re-verifies the DPM plan,
requires the reviewed checksum, applies the schema under DPM's execution lease,
asserts pgvector capability, reconciles the derived ANN projection, and proves
final schema convergence. The Supabase profile additionally revokes browser
roles and verifies that only the server-side `service_role` can access the
private product schema.

The exact table stores unindexed `extensions.vector(4100)` values. A separate
one-to-one table stores `extensions.halfvec(4000)` under HNSW for candidate
generation. Queries rerank those candidates against all 4,100 exact values;
the indexed projection never becomes the authoritative embedding.
