-- Where The Food At — "visited" marker (v4)
-- Run once in Supabase: SQL Editor → New query → paste → Run. Safe to re-run.
-- (Also included at the end of schema.sql for fresh set-ups.)

alter table public.places add column if not exists visited boolean not null default false;
