-- Where The Food At: cuisine (v6). Run once in Supabase SQL Editor. Safe to re-run.
alter table public.places add column if not exists cuisine text;
