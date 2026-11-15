-- Where The Food At — Google Places search (v3)
-- Run once in Supabase: SQL Editor → New query → paste → Run. Safe to re-run.
-- (Also included at the end of schema.sql for fresh set-ups.)

-- Which Google place a saved entry was filled from, and when that snapshot was taken.
alter table public.places add column if not exists google_place_id text;
alter table public.places add column if not exists snapshot_at timestamptz;

-- Daily usage counter for the `places` Edge Function (the app's own spending cap).
create table if not exists public.places_api_usage (
  day   date    not null default current_date,
  kind  text    not null,            -- 'search' | 'details'
  count integer not null default 0,
  primary key (day, kind)
);
alter table public.places_api_usage enable row level security;
-- No policies on purpose: only the Edge Function (service role) can read or write it.

-- Adds one to today's counter and says whether we're still under the limit.
create or replace function public.bump_places_usage(p_kind text, p_limit integer)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  n integer;
begin
  insert into public.places_api_usage (day, kind, count)
  values (current_date, p_kind, 1)
  on conflict (day, kind) do update set count = public.places_api_usage.count + 1
  returning count into n;
  return n <= p_limit;
end;
$$;

-- Only the Edge Function may call this; otherwise a signed-in user could use up the daily cap.
revoke all on function public.bump_places_usage(text, integer) from public, anon, authenticated;
grant execute on function public.bump_places_usage(text, integer) to service_role;
