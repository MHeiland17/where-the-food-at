-- Where The Food At — Supabase schema (lightweight, manual-entry pass)
-- Run this once in Supabase: Dashboard → SQL Editor → New query → paste → Run.
-- Safe to re-run: it drops and recreates the policies, function and trigger, but NOT the tables
-- (tables use "if not exists").

-- ─────────────────────────────────────────────────────────────
-- Tables
-- ─────────────────────────────────────────────────────────────

create table if not exists public.workspaces (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  created_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now()
);

create table if not exists public.workspace_members (
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id      uuid not null references auth.users(id) on delete cascade,
  role         text not null default 'editor' check (role in ('owner', 'editor')),
  primary key (workspace_id, user_id)
);

create table if not exists public.places (
  id              uuid primary key default gen_random_uuid(),
  workspace_id    uuid not null references public.workspaces(id) on delete cascade,
  created_by      uuid references auth.users(id) on delete set null default auth.uid(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  -- basics
  name            text not null,
  category        text,                       -- restaurant, cafe, bar, pub, takeaway, bakery, other
  street          text,
  suburb          text,
  postcode        text,
  state           text,
  phone           text,
  website         text,

  -- filters
  price_level     smallint check (price_level between 1 and 4),
  meals           text[] not null default '{}',     -- breakfast, brunch, lunch, dinner
  hours           jsonb  not null default '{}'::jsonb,
                  -- {"mon":[["11:30","15:00"],["17:30","22:00"]], "tue":[], ...}
                  -- empty object = hours unknown; a day with [] = closed that day
  max_group_size  smallint check (max_group_size > 0),
  booking_method  text not null default 'unknown'
                  check (booking_method in ('online', 'phone', 'walk_in', 'unknown')),
  booking_url     text,
  booking_notes   text,
  delivery        boolean,
  takeaway        boolean,
  public_rating   numeric(2,1) check (public_rating between 0 and 5),
  our_rating      smallint check (our_rating between 1 and 5),
  parking_ease    smallint check (parking_ease between 1 and 3),   -- 1 hard, 2 ok, 3 easy
  parking_notes   text,
  tags            text[] not null default '{}',
  notes           text
);

create index if not exists places_workspace_idx on public.places (workspace_id);

-- Added in v2 (food & drink, kitchen hours, public transport).
-- "add column if not exists" makes this safe on both new and existing projects.
alter table public.places add column if not exists food text not null default 'meals';   -- meals | snacks | none
alter table public.places add column if not exists meals_auto boolean not null default true; -- meals worked out from hours
alter table public.places add column if not exists kitchen_closes text;    -- "21:00"; null = same as closing
alter table public.places add column if not exists hours_note text;
alter table public.places add column if not exists alcohol text;           -- licensed | byo | licensed_byo | none; null = unknown
alter table public.places add column if not exists transport_ease smallint; -- 1 hard, 2 ok, 3 easy
alter table public.places add column if not exists transport_notes text;

alter table public.places drop constraint if exists places_food_check;
alter table public.places add constraint places_food_check check (food in ('meals', 'snacks', 'none'));
alter table public.places drop constraint if exists places_alcohol_check;
alter table public.places add constraint places_alcohol_check check (alcohol in ('licensed', 'byo', 'licensed_byo', 'none'));
alter table public.places drop constraint if exists places_transport_check;
alter table public.places add constraint places_transport_check check (transport_ease between 1 and 3);
alter table public.places drop constraint if exists places_kitchen_check;
alter table public.places add constraint places_kitchen_check check (kitchen_closes ~ '^\d{2}:\d{2}$');
-- meals now also allows 'snacks': breakfast, brunch, lunch, dinner, snacks

-- ─────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────

-- Is the signed-in user a member of this workspace?
-- SECURITY DEFINER so policies can call it without recursing into workspace_members' own policy.
create or replace function public.is_member(ws uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.workspace_members
    where workspace_id = ws and user_id = auth.uid()
  );
$$;

-- Keep updated_at current.
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists places_touch_updated_at on public.places;
create trigger places_touch_updated_at
  before update on public.places
  for each row execute function public.touch_updated_at();

-- Every new user gets their own workspace automatically.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  ws uuid;
begin
  insert into public.workspaces (name, created_by)
  values ('My places', new.id)
  returning id into ws;

  insert into public.workspace_members (workspace_id, user_id, role)
  values (ws, new.id, 'owner');

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ─────────────────────────────────────────────────────────────
-- Row-level security: you only see workspaces you belong to
-- ─────────────────────────────────────────────────────────────

alter table public.workspaces        enable row level security;
alter table public.workspace_members enable row level security;
alter table public.places            enable row level security;

drop policy if exists "members read workspaces" on public.workspaces;
create policy "members read workspaces" on public.workspaces
  for select to authenticated using (public.is_member(id));

drop policy if exists "members rename workspaces" on public.workspaces;
create policy "members rename workspaces" on public.workspaces
  for update to authenticated using (public.is_member(id)) with check (public.is_member(id));

drop policy if exists "members read memberships" on public.workspace_members;
create policy "members read memberships" on public.workspace_members
  for select to authenticated using (public.is_member(workspace_id));

drop policy if exists "members read places" on public.places;
create policy "members read places" on public.places
  for select to authenticated using (public.is_member(workspace_id));

drop policy if exists "members add places" on public.places;
create policy "members add places" on public.places
  for insert to authenticated with check (public.is_member(workspace_id));

drop policy if exists "members edit places" on public.places;
create policy "members edit places" on public.places
  for update to authenticated
  using (public.is_member(workspace_id)) with check (public.is_member(workspace_id));

drop policy if exists "members delete places" on public.places;
create policy "members delete places" on public.places
  for delete to authenticated using (public.is_member(workspace_id));

-- Adding / removing members is done by you in the SQL editor (see SUPABASE_SETUP.md, step 6),
-- so there are deliberately no insert/delete policies on workspace_members.

-- ─────────────────────────────────────────────────────────────
-- v3: Google Places search (same as 002_google_search.sql)
-- ─────────────────────────────────────────────────────────────
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

-- ─────────────────────────────────────────────────────────────
-- v4: "visited" marker (same as 003_visited.sql)
-- ─────────────────────────────────────────────────────────────
alter table public.places add column if not exists visited boolean not null default false;
