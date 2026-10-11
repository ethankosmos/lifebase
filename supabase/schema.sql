-- LifeBase Community: database and access rules.
-- Paste this whole file into Supabase › SQL Editor › New query, and run it once.
--
-- What lives here: display names, groups, and only what people choose to share
-- (posts, comments, reactions, challenge totals, shared expenses). Nothing else
-- from LifeBase ever leaves a person's device.
--
-- Every table has row-level security: you can only read things in groups you
-- belong to, and only change things you created.

-- ---------- tables ----------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 40),
  created_at timestamptz not null default now()
);

create table if not exists public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 60),
  invite_code text not null unique default upper(substr(md5(gen_random_uuid()::text), 1, 8)),
  owner uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.group_members (
  group_id uuid not null references public.groups(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  author uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  area text not null default 'other' check (area in ('plan','money','property','jobs','health','people','other')),
  title text not null check (char_length(title) between 1 and 200),
  body text not null default '' check (char_length(body) <= 2000),
  created_at timestamptz not null default now()
);

create table if not exists public.reactions (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  kind text not null default 'clap' check (kind in ('clap','fire','heart')),
  primary key (post_id, user_id, kind)
);

create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  author uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 1000),
  created_at timestamptz not null default now()
);

create table if not exists public.challenges (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  created_by uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 80),
  unit text not null default 'workouts' check (unit in ('workouts','minutes','custom')),
  unit_label text not null default '' check (char_length(unit_label) <= 30),
  target numeric check (target is null or target > 0),
  starts date not null,
  ends date not null check (ends >= starts),
  created_at timestamptz not null default now()
);

create table if not exists public.challenge_entries (
  challenge_id uuid not null references public.challenges(id) on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  total numeric not null default 0 check (total >= 0 and total < 100000),
  updated_at timestamptz not null default now(),
  primary key (challenge_id, user_id)
);

create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  created_by uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  paid_by uuid not null references public.profiles(id) on delete cascade,
  description text not null check (char_length(description) between 1 and 120),
  amount numeric(12,2) not null check (amount > 0 and amount < 1000000),
  spent_on date not null default current_date,
  created_at timestamptz not null default now()
);

create table if not exists public.expense_splits (
  expense_id uuid not null references public.expenses(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  share numeric(12,2) not null check (share >= 0),
  primary key (expense_id, user_id)
);

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups(id) on delete cascade,
  created_by uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  from_user uuid not null references public.profiles(id) on delete cascade,
  to_user uuid not null references public.profiles(id) on delete cascade,
  amount numeric(12,2) not null check (amount > 0 and amount < 1000000),
  created_at timestamptz not null default now(),
  check (from_user <> to_user)
);

-- ---------- helpers (run with elevated rights, but only answer about the caller) ----------
create or replace function public.is_member(g uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from group_members where group_id = g and user_id = auth.uid())
$$;

create or replace function public.shares_group(u uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from group_members a join group_members b on a.group_id = b.group_id
    where a.user_id = auth.uid() and b.user_id = u)
$$;

create or replace function public.post_group(p uuid) returns uuid
language sql stable security definer set search_path = public as $$ select group_id from posts where id = p $$;
create or replace function public.challenge_group(c uuid) returns uuid
language sql stable security definer set search_path = public as $$ select group_id from challenges where id = c $$;
create or replace function public.expense_group(e uuid) returns uuid
language sql stable security definer set search_path = public as $$ select group_id from expenses where id = e $$;
create or replace function public.expense_creator(e uuid) returns uuid
language sql stable security definer set search_path = public as $$ select created_by from expenses where id = e $$;

-- New account → profile, using the name given at sign-up
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, name)
  values (new.id, left(coalesce(nullif(trim(new.raw_user_meta_data->>'name'), ''), split_part(new.email, '@', 1)), 40))
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- Whoever creates a group is its first member
create or replace function public.add_owner_as_member() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into group_members (group_id, user_id) values (new.id, new.owner) on conflict do nothing;
  return new;
end $$;
drop trigger if exists on_group_created on public.groups;
create trigger on_group_created after insert on public.groups for each row execute function public.add_owner_as_member();

-- Join with an invite code (the only way to become a member of someone else's group)
create or replace function public.join_group(code text) returns uuid
language plpgsql security definer set search_path = public as $$
declare g uuid;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  select id into g from groups where invite_code = upper(trim(code));
  if g is null then raise exception 'No group with that code'; end if;
  insert into group_members (group_id, user_id) values (g, auth.uid()) on conflict do nothing;
  return g;
end $$;

-- Delete everything this person has in Community (their sign-in is removed by the trigger below or by the admin)
create or replace function public.delete_my_community_data() returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  delete from profiles where id = auth.uid();   -- cascades to memberships, posts, comments, reactions, entries, expenses, owned groups
end $$;

-- ---------- row-level security ----------
alter table public.profiles enable row level security;
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.posts enable row level security;
alter table public.reactions enable row level security;
alter table public.comments enable row level security;
alter table public.challenges enable row level security;
alter table public.challenge_entries enable row level security;
alter table public.expenses enable row level security;
alter table public.expense_splits enable row level security;
alter table public.payments enable row level security;

-- profiles: see yourself and people you share a group with; edit only yourself
create policy profiles_read on public.profiles for select to authenticated using (id = auth.uid() or public.shares_group(id));
create policy profiles_insert on public.profiles for insert to authenticated with check (id = auth.uid());
create policy profiles_update on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- groups: members can see; anyone signed in can create one they own; only the owner renames or deletes
create policy groups_read on public.groups for select to authenticated using (public.is_member(id) or owner = auth.uid());
create policy groups_create on public.groups for insert to authenticated with check (owner = auth.uid());
create policy groups_update on public.groups for update to authenticated using (owner = auth.uid()) with check (owner = auth.uid());
create policy groups_delete on public.groups for delete to authenticated using (owner = auth.uid());

-- members: see your groups' members; leave yourself, or the owner removes someone
create policy members_read on public.group_members for select to authenticated using (public.is_member(group_id));
create policy members_leave on public.group_members for delete to authenticated
  using (user_id = auth.uid() or exists (select 1 from public.groups g where g.id = group_id and g.owner = auth.uid()));

-- posts
create policy posts_read on public.posts for select to authenticated using (public.is_member(group_id));
create policy posts_create on public.posts for insert to authenticated with check (author = auth.uid() and public.is_member(group_id));
create policy posts_update on public.posts for update to authenticated using (author = auth.uid()) with check (author = auth.uid() and public.is_member(group_id));
create policy posts_delete on public.posts for delete to authenticated using (author = auth.uid());

-- reactions
create policy reactions_read on public.reactions for select to authenticated using (public.is_member(public.post_group(post_id)));
create policy reactions_create on public.reactions for insert to authenticated with check (user_id = auth.uid() and public.is_member(public.post_group(post_id)));
create policy reactions_delete on public.reactions for delete to authenticated using (user_id = auth.uid());

-- comments
create policy comments_read on public.comments for select to authenticated using (public.is_member(public.post_group(post_id)));
create policy comments_create on public.comments for insert to authenticated with check (author = auth.uid() and public.is_member(public.post_group(post_id)));
create policy comments_delete on public.comments for delete to authenticated using (author = auth.uid());

-- challenges
create policy challenges_read on public.challenges for select to authenticated using (public.is_member(group_id));
create policy challenges_create on public.challenges for insert to authenticated with check (created_by = auth.uid() and public.is_member(group_id));
create policy challenges_update on public.challenges for update to authenticated using (created_by = auth.uid()) with check (created_by = auth.uid() and public.is_member(group_id));
create policy challenges_delete on public.challenges for delete to authenticated using (created_by = auth.uid());

-- challenge entries: everyone in the group sees the leaderboard; you only set your own total
create policy entries_read on public.challenge_entries for select to authenticated using (public.is_member(public.challenge_group(challenge_id)));
create policy entries_create on public.challenge_entries for insert to authenticated with check (user_id = auth.uid() and public.is_member(public.challenge_group(challenge_id)));
create policy entries_update on public.challenge_entries for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid() and public.is_member(public.challenge_group(challenge_id)));
create policy entries_delete on public.challenge_entries for delete to authenticated using (user_id = auth.uid());

-- shared expenses: group members see them; the person who added one manages it
create policy expenses_read on public.expenses for select to authenticated using (public.is_member(group_id));
create policy expenses_create on public.expenses for insert to authenticated
  with check (created_by = auth.uid() and public.is_member(group_id)
              and exists (select 1 from public.group_members m where m.group_id = expenses.group_id and m.user_id = paid_by));
create policy expenses_delete on public.expenses for delete to authenticated using (created_by = auth.uid());

create policy splits_read on public.expense_splits for select to authenticated using (public.is_member(public.expense_group(expense_id)));
create policy splits_create on public.expense_splits for insert to authenticated
  with check (public.expense_creator(expense_id) = auth.uid()
              and exists (select 1 from public.group_members m where m.group_id = public.expense_group(expense_id) and m.user_id = expense_splits.user_id));
create policy splits_delete on public.expense_splits for delete to authenticated using (public.expense_creator(expense_id) = auth.uid());

-- payments ("I paid you back"): either person involved can record it
create policy payments_read on public.payments for select to authenticated using (public.is_member(group_id));
create policy payments_create on public.payments for insert to authenticated
  with check (created_by = auth.uid() and public.is_member(group_id) and auth.uid() in (from_user, to_user)
              and exists (select 1 from public.group_members m where m.group_id = payments.group_id and m.user_id = from_user)
              and exists (select 1 from public.group_members m where m.group_id = payments.group_id and m.user_id = to_user));
create policy payments_delete on public.payments for delete to authenticated using (created_by = auth.uid());

-- Signed-out visitors get nothing
revoke all on all tables in schema public from anon;
revoke execute on function public.join_group(text), public.delete_my_community_data() from anon, public;
grant execute on function public.join_group(text), public.delete_my_community_data() to authenticated;
