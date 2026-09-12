-- fanwaave: private application namespace inside the shared oresoftware Supabase project.
begin;

create schema if not exists fanwaave;
comment on schema fanwaave is 'fanwaave application namespace; Shared Auth remains authoritative for identity.';

revoke all on schema fanwaave from public, anon, authenticated;
alter default privileges in schema fanwaave revoke all on tables from public, anon, authenticated;
alter default privileges in schema fanwaave revoke all on sequences from public, anon, authenticated;
alter default privileges in schema fanwaave revoke all on functions from public, anon, authenticated;

commit;
