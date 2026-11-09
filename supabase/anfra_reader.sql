-- =============================================================================
-- A read-only Postgres role for Anfra
--
-- Anfra only ever reads. Giving it its own login with SELECT-only privileges
-- means an exploratory query can never change your data.
--
-- Replace the password below, then run in the Supabase SQL Editor or with:
--   psql "$SUPABASE_DB_URL" -v reader_password="'<a-strong-password>'" -f supabase/anfra_reader.sql
-- =============================================================================

\if :{?reader_password}
\else
  \set reader_password '''change-me-to-a-strong-password'''
\endif

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anfra_reader') then
    create role anfra_reader login;
  end if;
end
$$;

alter role anfra_reader with login password :reader_password;

-- Read access to the demo schema only
grant usage  on schema ecommerce to anfra_reader;
grant select on all tables in schema ecommerce to anfra_reader;
alter default privileges in schema ecommerce grant select on tables to anfra_reader;

-- Guard rails: cap runaway queries
alter role anfra_reader set statement_timeout = '60s';
alter role anfra_reader set default_transaction_read_only = on;
