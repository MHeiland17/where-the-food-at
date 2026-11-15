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
drop policy if exists "owners rename workspaces" on public.workspaces;
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

-- ═════════════════════════════════════════════════════════════
-- v5: shared lists (same as 004_shared_lists.sql)
-- ═════════════════════════════════════════════════════════════
-- ─────────────────────────────────────────────────────────────
-- 1. List kinds, membership dates, invites
-- ─────────────────────────────────────────────────────────────
alter table public.workspaces add column if not exists kind text not null default 'personal';
alter table public.workspaces drop constraint if exists workspaces_kind_check;
alter table public.workspaces add constraint workspaces_kind_check check (kind in ('personal', 'shared'));

alter table public.workspace_members add column if not exists created_at timestamptz not null default now();

create table if not exists public.workspace_invites (
  token        text primary key default (replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '')),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  created_by   uuid not null references auth.users(id) on delete cascade default auth.uid(),
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null default now() + interval '7 days',
  accepted_by  uuid references auth.users(id) on delete set null,
  accepted_at  timestamptz
);
alter table public.workspace_invites enable row level security;
-- No policies on purpose: invites are only touched through the functions below.

-- ─────────────────────────────────────────────────────────────
-- 2. Helpers (used by the security rules)
-- ─────────────────────────────────────────────────────────────
create or replace function public.is_owner(ws uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from public.workspace_members
    where workspace_id = ws and user_id = auth.uid() and role = 'owner'
  );
$$;

-- The personal list of a user.
create or replace function public.personal_workspace_of(p_user uuid)
returns uuid language sql security definer stable set search_path = public as $$
  select w.id
  from public.workspaces w
  join public.workspace_members m on m.workspace_id = w.id
  where w.kind = 'personal' and m.user_id = p_user and m.role = 'owner'
  order by w.created_at
  limit 1;
$$;

-- A friendly name for a user (Google name, else the part of the email before @).
create or replace function public.display_name_of(p_user uuid)
returns text language sql security definer stable set search_path = public as $$
  select coalesce(
    nullif(u.raw_user_meta_data ->> 'full_name', ''),
    nullif(u.raw_user_meta_data ->> 'name', ''),
    split_part(u.email, '@', 1)
  )
  from auth.users u where u.id = p_user;
$$;

-- Can the signed-in user SEE the places in list `ws`?
-- Yes if it's their own list, or it's the personal list of someone they share a list with.
create or replace function public.can_view_places(ws uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select public.is_member(ws) or exists (
    select 1
    from public.workspaces pw
    join public.workspace_members owner_m on owner_m.workspace_id = pw.id and owner_m.role = 'owner'
    join public.workspace_members theirs  on theirs.user_id = owner_m.user_id
    join public.workspaces sw             on sw.id = theirs.workspace_id and sw.kind = 'shared'
    join public.workspace_members mine    on mine.workspace_id = sw.id and mine.user_id = auth.uid()
    where pw.id = ws and pw.kind = 'personal'
  );
$$;

-- Can the signed-in user ADD / EDIT / DELETE places in list `ws`? Only in their own personal list.
create or replace function public.can_edit_places(ws uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1
    from public.workspaces w
    join public.workspace_members m on m.workspace_id = w.id
    where w.id = ws and w.kind = 'personal' and m.user_id = auth.uid()
  );
$$;

-- ─────────────────────────────────────────────────────────────
-- 3. Security rules
-- ─────────────────────────────────────────────────────────────
drop policy if exists "members read places" on public.places;
create policy "members read places" on public.places
  for select to authenticated using (public.can_view_places(workspace_id));

drop policy if exists "members add places" on public.places;
create policy "members add places" on public.places
  for insert to authenticated with check (public.can_edit_places(workspace_id));

drop policy if exists "members edit places" on public.places;
create policy "members edit places" on public.places
  for update to authenticated
  using (public.can_edit_places(workspace_id)) with check (public.can_edit_places(workspace_id));

drop policy if exists "members delete places" on public.places;
create policy "members delete places" on public.places
  for delete to authenticated using (public.can_edit_places(workspace_id));

drop policy if exists "members rename workspaces" on public.workspaces;
drop policy if exists "owners rename workspaces" on public.workspaces;
create policy "owners rename workspaces" on public.workspaces
  for update to authenticated using (public.is_owner(id)) with check (public.is_owner(id));

-- ─────────────────────────────────────────────────────────────
-- 4. Actions the app calls
-- ─────────────────────────────────────────────────────────────
create or replace function public.create_shared_list(p_name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  ws uuid;
  n  text := btrim(coalesce(p_name, ''));
begin
  if auth.uid() is null then raise exception 'Please sign in first.'; end if;
  if length(n) < 1 or length(n) > 60 then raise exception 'List names need 1 to 60 characters.'; end if;
  insert into public.workspaces (name, created_by, kind) values (n, auth.uid(), 'shared') returning id into ws;
  insert into public.workspace_members (workspace_id, user_id, role) values (ws, auth.uid(), 'owner');
  return ws;
end;
$$;

create or replace function public.create_invite(p_workspace uuid)
returns text language plpgsql security definer set search_path = public as $$
declare
  t text;
begin
  if not exists (select 1 from public.workspaces where id = p_workspace and kind = 'shared') then
    raise exception 'Only shared lists can have invites.';
  end if;
  if not public.is_owner(p_workspace) then
    raise exception 'Only the person who created this list can invite people.';
  end if;
  insert into public.workspace_invites (workspace_id, created_by) values (p_workspace, auth.uid()) returning token into t;
  return t;
end;
$$;

-- What an invite link is for, before accepting it.
create or replace function public.peek_invite(p_token text)
returns table (list_id uuid, list_name text, inviter text, invite_status text)
language plpgsql security definer stable set search_path = public as $$
begin
  return query
  select i.workspace_id, w.name, public.display_name_of(i.created_by),
    case
      when public.is_member(i.workspace_id) then 'member'
      when i.accepted_at is not null then 'used'
      when i.expires_at < now() then 'expired'
      else 'ok'
    end
  from public.workspace_invites i
  join public.workspaces w on w.id = i.workspace_id
  where i.token = p_token;
end;
$$;

create or replace function public.accept_invite(p_token text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  inv public.workspace_invites%rowtype;
begin
  if auth.uid() is null then raise exception 'Please sign in first.'; end if;
  select * into inv from public.workspace_invites where token = p_token for update;
  if not found then raise exception 'This invite link isn''t valid.'; end if;
  if public.is_member(inv.workspace_id) then return inv.workspace_id; end if;
  if inv.accepted_at is not null then raise exception 'This invite link has already been used. Ask for a new one.'; end if;
  if inv.expires_at < now() then raise exception 'This invite link has expired. Ask for a new one.'; end if;
  insert into public.workspace_members (workspace_id, user_id, role)
  values (inv.workspace_id, auth.uid(), 'editor')
  on conflict do nothing;
  update public.workspace_invites set accepted_by = auth.uid(), accepted_at = now() where token = p_token;
  return inv.workspace_id;
end;
$$;

-- Everyone in a list, with the personal list whose places they contribute.
create or replace function public.list_members(p_workspace uuid)
returns table (member_id uuid, member_role text, member_name text, member_email text, personal_list uuid, joined_at timestamptz)
language plpgsql security definer stable set search_path = public as $$
begin
  if not public.is_member(p_workspace) then raise exception 'You''re not in this list.'; end if;
  return query
  select m.user_id, m.role, public.display_name_of(m.user_id), u.email::text,
         public.personal_workspace_of(m.user_id), m.created_at
  from public.workspace_members m
  join auth.users u on u.id = m.user_id
  where m.workspace_id = p_workspace
  order by (m.role = 'owner') desc, m.created_at;
end;
$$;

create or replace function public.remove_member(p_workspace uuid, p_user uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.workspaces where id = p_workspace and kind = 'shared') then
    raise exception 'Only shared lists have members to remove.';
  end if;
  if not public.is_owner(p_workspace) then raise exception 'Only the list creator can remove people.'; end if;
  if p_user = auth.uid() then raise exception 'You created this list. Delete it instead.'; end if;
  delete from public.workspace_members where workspace_id = p_workspace and user_id = p_user;
end;
$$;

create or replace function public.leave_list(p_workspace uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.workspaces where id = p_workspace and kind = 'shared') then
    raise exception 'You can only leave shared lists.';
  end if;
  if public.is_owner(p_workspace) then raise exception 'You created this list. Delete it instead.'; end if;
  delete from public.workspace_members where workspace_id = p_workspace and user_id = auth.uid();
end;
$$;

-- Deletes the shared list for everyone. Places are untouched (they live in each person's own list).
create or replace function public.delete_shared_list(p_workspace uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.workspaces where id = p_workspace and kind = 'shared') then
    raise exception 'Only shared lists can be deleted.';
  end if;
  if not public.is_owner(p_workspace) then raise exception 'Only the list creator can delete it.'; end if;
  delete from public.workspaces where id = p_workspace;
end;
$$;

-- ─────────────────────────────────────────────────────────────
-- 5. Who may call what
-- ─────────────────────────────────────────────────────────────
-- Internal helpers: not callable directly by app users.
revoke all on function public.display_name_of(uuid) from public, anon, authenticated;
revoke all on function public.personal_workspace_of(uuid) from public, anon, authenticated;

-- App actions: signed-in users only.
revoke all on function public.create_shared_list(text) from public, anon;
revoke all on function public.create_invite(uuid) from public, anon;
revoke all on function public.peek_invite(text) from public, anon;
revoke all on function public.accept_invite(text) from public, anon;
revoke all on function public.list_members(uuid) from public, anon;
revoke all on function public.remove_member(uuid, uuid) from public, anon;
revoke all on function public.leave_list(uuid) from public, anon;
revoke all on function public.delete_shared_list(uuid) from public, anon;
grant execute on function public.create_shared_list(text) to authenticated;
grant execute on function public.create_invite(uuid) to authenticated;
grant execute on function public.peek_invite(text) to authenticated;
grant execute on function public.accept_invite(text) to authenticated;
grant execute on function public.list_members(uuid) to authenticated;
grant execute on function public.remove_member(uuid, uuid) to authenticated;
grant execute on function public.leave_list(uuid) to authenticated;
grant execute on function public.delete_shared_list(uuid) to authenticated;
