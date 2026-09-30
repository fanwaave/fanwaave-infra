# Fanwaave contact worker

`fanwaave-contact-worker.rs` is a queue consumer, not an inbound service. Postgres is authoritative; optional NATS traffic only wakes consumers and fans out delivery results.

## Runtime secret contract

Create the Kubernetes secret `fanwaave-contact-runtime` through the normal encrypted SOPS+age / secret-manager path. Do **not** commit a plaintext Secret manifest.

Required keys:

- `database-url`
- `enqueue-secret` (API only)

Provider keys are required only for channels enabled in a given environment:

- `sendgrid-api-key`
- `email-from`
- `twilio-account-sid`
- `twilio-auth-token`
- `twilio-from-number`
- `nats-url` (optional)

## Burst execution

`k8s/contact-worker-drain-job.yaml` is tuned for a bounded worker that claims at most 10,000 jobs and exits. The default email admission rate is 20 provider requests/second with 64 requests in flight, which is enough theoretical request capacity for 10,000 sends inside ten minutes. Actual completion time is bounded by provider/account quotas, response latency, retries, suppression checks, and database performance.

Launch separate uniquely named Jobs for concurrent campaign drains rather than turning the worker into a permanent high-throughput Deployment. PostgreSQL `SKIP LOCKED` leases partition work across replicas safely.

For steady low-volume delivery, run the same image without `--drain`/`--max-jobs` as a single-replica Deployment or through the preferred Scintilla-run launcher. Keep the same database lease semantics; do not introduce an in-memory-only queue.

## Failure behavior

- provider 408/409/425/429/5xx -> durable retry with backoff
- other provider 4xx -> terminal `dead`
- unsubscribe/bounce/complaint/invalid/manual suppression -> no provider request, terminal suppressed attempt
- process crash -> lease expires and another worker reclaims the job
- NATS outage -> worker/API continue through Postgres polling
- database outage -> fail closed; no provider send is attempted without durable queue state
