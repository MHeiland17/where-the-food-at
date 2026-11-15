-- Where The Food At — shared lists (v5)
-- Run once in Supabase: SQL Editor → New query → paste → Run. Safe to re-run.
-- (Also included at the end of schema.sql for fresh set-ups.)
--
-- Model
--   • Every user has one PERSONAL list ("My places"). Places always live in a personal list.
--   • A SHARED list holds no places of its own: it shows the personal places of all its members.
--   • Only the person whose personal list a place is in can edit or delete it.
--   • People join a shared list through a single-use invite link (7 days).

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
