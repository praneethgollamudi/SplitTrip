-- SplitTrip shared schema. Run in Supabase SQL Editor.
create extension if not exists pgcrypto;
create table if not exists public.trips (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 1 and 100),
  invite_code text not null unique check (invite_code ~ '^[A-Z2-9]{6}$'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);
create table if not exists public.trip_members (
  trip_id uuid not null references public.trips(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner','member')),
  display_name text not null default '',
  joined_at timestamptz not null default now(),
  primary key (trip_id,user_id)
);
create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips(id) on delete cascade,
  description text not null check (char_length(trim(description)) between 1 and 160),
  amount numeric(12,2) not null check (amount > 0 and amount <= 100000000),
  category text not null default 'Other' check (category in ('Food & drinks','Transport','Accommodation','Activities','Other')),
  payer_id uuid not null references auth.users(id) on delete restrict,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);
create table if not exists public.expense_shares (
  expense_id uuid not null references public.expenses(id) on delete cascade,
  trip_id uuid not null references public.trips(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete restrict,
  amount numeric(12,2) not null check (amount >= 0),
  primary key (expense_id,user_id)
);
create index if not exists expenses_trip_created_idx on public.expenses(trip_id,created_at desc);
create index if not exists shares_trip_idx on public.expense_shares(trip_id);

alter table public.trips enable row level security;
alter table public.trip_members enable row level security;
alter table public.expenses enable row level security;
alter table public.expense_shares enable row level security;

-- SECURITY DEFINER functions use a fixed search_path and check auth.uid().
create or replace function public.create_trip(p_name text, p_invite_code text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare new_trip_id uuid;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  if char_length(trim(p_name)) not between 1 and 100 then raise exception 'Trip name must be 1–100 characters'; end if;
  if p_invite_code !~ '^[A-Z2-9]{6}$' then raise exception 'Invalid invite code format'; end if;
  insert into public.trips(name,invite_code,created_by) values(trim(p_name),p_invite_code,auth.uid()) returning id into new_trip_id;
  insert into public.trip_members(trip_id,user_id,role,display_name) values(new_trip_id,auth.uid(),'owner',coalesce((select nullif(trim(raw_user_meta_data->>'name'),'') from auth.users where id=auth.uid()),split_part((select email from auth.users where id=auth.uid()),'@',1)));
  return new_trip_id;
end; $$;
create or replace function public.join_trip(p_invite_code text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare target_id uuid; user_email text; user_name text;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  select id into target_id from public.trips where invite_code=upper(trim(p_invite_code));
  if target_id is null then raise exception 'Invite code not found'; end if;
  select email,coalesce(nullif(trim(raw_user_meta_data->>'name'),''),split_part(email,'@',1)) into user_email,user_name from auth.users where id=auth.uid();
  insert into public.trip_members(trip_id,user_id,role,display_name) values(target_id,auth.uid(),'member',coalesce(user_name,'Member')) on conflict(trip_id,user_id) do nothing;
  return target_id;
end; $$;
revoke all on function public.create_trip(text,text) from public;
revoke all on function public.join_trip(text) from public;
grant execute on function public.create_trip(text,text) to authenticated;
grant execute on function public.join_trip(text) to authenticated;

-- Helper predicates bypass RLS only for these narrow boolean checks, avoiding
-- recursive policies on trip_members. The search_path is fixed to prevent shadowing.
create or replace function public.is_trip_member(p_trip_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.trip_members tm where tm.trip_id=p_trip_id and tm.user_id=auth.uid());
$$;
create or replace function public.is_trip_owner(p_trip_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.trip_members tm where tm.trip_id=p_trip_id and tm.user_id=auth.uid() and tm.role='owner');
$$;
revoke all on function public.is_trip_member(uuid) from public;
revoke all on function public.is_trip_owner(uuid) from public;
grant execute on function public.is_trip_member(uuid) to authenticated;
grant execute on function public.is_trip_owner(uuid) to authenticated;

drop policy if exists trips_select_members on public.trips;
drop policy if exists trips_insert_blocked on public.trips;
drop policy if exists trips_update_owner on public.trips;
drop policy if exists trips_delete_owner on public.trips;
drop policy if exists trip_members_select_peers on public.trip_members;
drop policy if exists trip_members_insert_self on public.trip_members;
drop policy if exists trip_members_insert_blocked on public.trip_members;
drop policy if exists trip_members_delete_self_or_owner on public.trip_members;
drop policy if exists trip_members_update_owner on public.trip_members;
drop policy if exists expenses_select_members on public.expenses;
drop policy if exists expenses_insert_members on public.expenses;
drop policy if exists expenses_update_creator_or_owner on public.expenses;
drop policy if exists expenses_delete_creator_or_owner on public.expenses;
drop policy if exists shares_select_members on public.expense_shares;
drop policy if exists shares_insert_members on public.expense_shares;
drop policy if exists shares_delete_creator_or_owner on public.expense_shares;

-- A user can see trip rows only if they are a member. Joining is performed only
-- by join_trip(), which validates the invite code; direct membership inserts are blocked.
create policy trips_select_members on public.trips for select to authenticated
  using (public.is_trip_member(id));
create policy trips_insert_blocked on public.trips for insert to authenticated with check (false);
create policy trips_update_owner on public.trips for update to authenticated
  using (public.is_trip_owner(id)) with check (public.is_trip_owner(id));
create policy trips_delete_owner on public.trips for delete to authenticated
  using (public.is_trip_owner(id));

create policy trip_members_select_peers on public.trip_members for select to authenticated
  using (public.is_trip_member(trip_id));
create policy trip_members_insert_blocked on public.trip_members for insert to authenticated with check (false);
create policy trip_members_delete_self_or_owner on public.trip_members for delete to authenticated
  using (user_id=auth.uid() or public.is_trip_owner(trip_id));
create policy trip_members_update_owner on public.trip_members for update to authenticated
  using (public.is_trip_owner(trip_id)) with check (public.is_trip_owner(trip_id));

create policy expenses_select_members on public.expenses for select to authenticated
  using (public.is_trip_member(trip_id));
create policy expenses_insert_members on public.expenses for insert to authenticated
  with check (created_by=auth.uid() and public.is_trip_member(trip_id) and exists(select 1 from public.trip_members payer where payer.trip_id=expenses.trip_id and payer.user_id=expenses.payer_id));
create policy expenses_update_creator_or_owner on public.expenses for update to authenticated
  using (created_by=auth.uid() or public.is_trip_owner(trip_id))
  with check (created_by=auth.uid() or public.is_trip_owner(trip_id));
create policy expenses_delete_creator_or_owner on public.expenses for delete to authenticated
  using (created_by=auth.uid() or public.is_trip_owner(trip_id));

create policy shares_select_members on public.expense_shares for select to authenticated
  using (public.is_trip_member(trip_id));
create policy shares_insert_members on public.expense_shares for insert to authenticated
  with check (public.is_trip_member(trip_id) and exists(select 1 from public.expenses e where e.id=expense_shares.expense_id and e.trip_id=expense_shares.trip_id and (e.created_by=auth.uid() or public.is_trip_owner(e.trip_id))) and exists(select 1 from public.trip_members share_member where share_member.trip_id=expense_shares.trip_id and share_member.user_id=expense_shares.user_id));
create policy shares_delete_creator_or_owner on public.expense_shares for delete to authenticated
  using (exists(select 1 from public.expenses e where e.id=expense_shares.expense_id and (e.created_by=auth.uid() or public.is_trip_owner(e.trip_id))));

-- Realtime publication (safe to run repeatedly).
do $$ begin
  alter publication supabase_realtime add table public.expenses;
exception when duplicate_object then null; when undefined_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.trip_members;
exception when duplicate_object then null; when undefined_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.expense_shares;
exception when duplicate_object then null; when undefined_object then null; end $$;
