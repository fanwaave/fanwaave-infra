-- Preview/local seed for fanwaave (auth). Runs only on local stacks and Supabase preview branches.
-- Keep it idempotent, synthetic, and inside the fanwaave schema. Never add real user data or credentials.
create schema if not exists fanwaave;
