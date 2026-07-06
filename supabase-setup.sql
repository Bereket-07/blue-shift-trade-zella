-- ============================================================
-- ZellaBek — Supabase setup
-- Run this ONCE in: Supabase dashboard → SQL Editor → New query
-- ============================================================

-- 1. Trades table
create table if not exists public.trades (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  trade_key text not null,
  open_time timestamptz not null,
  close_time timestamptz not null,
  symbol text not null,
  side text not null check (side in ('BUY','SELL')),
  lots numeric,
  entry numeric,
  exit numeric,
  sl numeric,
  tp numeric,
  commission numeric default 0,
  swap numeric default 0,
  profit numeric not null,
  setup text default '',
  emotion text default '',
  notes_pre text default '',
  notes_post text default '',
  shots jsonb default '[]'::jsonb,
  created_at timestamptz default now(),
  unique (user_id, trade_key)
);

create index if not exists trades_user_close_idx on public.trades (user_id, close_time);

-- 2. Row Level Security: every user sees ONLY their own trades
alter table public.trades enable row level security;

drop policy if exists "select own trades" on public.trades;
create policy "select own trades" on public.trades
  for select using (auth.uid() = user_id);

drop policy if exists "insert own trades" on public.trades;
create policy "insert own trades" on public.trades
  for insert with check (auth.uid() = user_id);

drop policy if exists "update own trades" on public.trades;
create policy "update own trades" on public.trades
  for update using (auth.uid() = user_id);

drop policy if exists "delete own trades" on public.trades;
create policy "delete own trades" on public.trades
  for delete using (auth.uid() = user_id);

-- 3. Private storage bucket for screenshots
insert into storage.buckets (id, name, public)
values ('screenshots', 'screenshots', false)
on conflict (id) do nothing;

-- Each user can only touch files inside their own folder (userId/...)
drop policy if exists "read own screenshots" on storage.objects;
create policy "read own screenshots" on storage.objects
  for select using (
    bucket_id = 'screenshots'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "upload own screenshots" on storage.objects;
create policy "upload own screenshots" on storage.objects
  for insert with check (
    bucket_id = 'screenshots'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "delete own screenshots" on storage.objects;
create policy "delete own screenshots" on storage.objects
  for delete using (
    bucket_id = 'screenshots'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

-- 4. Transactions table (deposits / withdrawals from statements)
create table if not exists public.transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  tx_key text not null,
  time timestamptz not null,
  label text default '',
  amount numeric not null,
  created_at timestamptz default now(),
  unique (user_id, tx_key)
);

alter table public.transactions enable row level security;

drop policy if exists "select own tx" on public.transactions;
create policy "select own tx" on public.transactions
  for select using (auth.uid() = user_id);

drop policy if exists "insert own tx" on public.transactions;
create policy "insert own tx" on public.transactions
  for insert with check (auth.uid() = user_id);

drop policy if exists "update own tx" on public.transactions;
create policy "update own tx" on public.transactions
  for update using (auth.uid() = user_id);

drop policy if exists "delete own tx" on public.transactions;
create policy "delete own tx" on public.transactions
  for delete using (auth.uid() = user_id);

-- 5. Playbooks table (user-defined strategies)
create table if not exists public.playbooks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  market text default '',
  timeframe text default '',
  entry_rules text default '',
  exit_rules text default '',
  risk_rules text default '',
  created_at timestamptz default now(),
  unique (user_id, name)
);

alter table public.playbooks enable row level security;

drop policy if exists "select own playbooks" on public.playbooks;
create policy "select own playbooks" on public.playbooks
  for select using (auth.uid() = user_id);

drop policy if exists "insert own playbooks" on public.playbooks;
create policy "insert own playbooks" on public.playbooks
  for insert with check (auth.uid() = user_id);

drop policy if exists "update own playbooks" on public.playbooks;
create policy "update own playbooks" on public.playbooks
  for update using (auth.uid() = user_id);

drop policy if exists "delete own playbooks" on public.playbooks;
create policy "delete own playbooks" on public.playbooks
  for delete using (auth.uid() = user_id);

-- ============================================================
-- 6. ADMIN SYSTEM — profiles, ratings, admin policies
-- ============================================================

-- Profiles: one row per user (usage tracking + admin/blocked flags)
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  created_at timestamptz default now(),
  last_seen timestamptz default now(),
  visits integer default 0,
  is_admin boolean default false,
  is_blocked boolean default false
);

alter table public.profiles enable row level security;

-- helper: is this user an admin? (security definer avoids RLS recursion)
create or replace function public.is_admin(uid uuid)
returns boolean language sql security definer stable
as $$ select coalesce((select is_admin from public.profiles where id = uid), false) $$;

drop policy if exists "select own or admin" on public.profiles;
create policy "select own or admin" on public.profiles
  for select using (auth.uid() = id or public.is_admin(auth.uid()));

drop policy if exists "insert own profile" on public.profiles;
create policy "insert own profile" on public.profiles
  for insert with check (auth.uid() = id);

drop policy if exists "update own profile" on public.profiles;
create policy "update own profile" on public.profiles
  for update using (auth.uid() = id);

-- users may only write safe columns (cannot make themselves admin/unblocked)
revoke insert on table public.profiles from authenticated;
revoke update on table public.profiles from authenticated;
grant insert (id, email) on table public.profiles to authenticated;
grant update (email, last_seen, visits) on table public.profiles to authenticated;

-- auto-create a profile whenever a new user signs up
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer
as $$ begin
  insert into public.profiles (id, email) values (new.id, new.email)
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- backfill profiles for users that already exist
insert into public.profiles (id, email)
select id, email from auth.users
on conflict (id) do nothing;

-- admin-only: block / unblock a user
create or replace function public.admin_set_blocked(target uuid, blocked boolean)
returns void language plpgsql security definer
as $$ begin
  if not public.is_admin(auth.uid()) then
    raise exception 'not allowed';
  end if;
  update public.profiles set is_blocked = blocked where id = target;
end $$;

-- Ratings: users rate the app (1–5 stars + feedback)
create table if not exists public.ratings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  stars integer not null check (stars between 1 and 5),
  feedback text default '',
  updated_at timestamptz default now()
);
alter table public.ratings enable row level security;

drop policy if exists "own rating select" on public.ratings;
create policy "own rating select" on public.ratings
  for select using (auth.uid() = user_id or public.is_admin(auth.uid()));
drop policy if exists "own rating insert" on public.ratings;
create policy "own rating insert" on public.ratings
  for insert with check (auth.uid() = user_id);
drop policy if exists "own rating update" on public.ratings;
create policy "own rating update" on public.ratings
  for update using (auth.uid() = user_id);
drop policy if exists "own rating delete" on public.ratings;
create policy "own rating delete" on public.ratings
  for delete using (auth.uid() = user_id);

-- Admins can see and delete everyone's data
drop policy if exists "admin select all trades" on public.trades;
create policy "admin select all trades" on public.trades
  for select using (public.is_admin(auth.uid()));
drop policy if exists "admin delete any trades" on public.trades;
create policy "admin delete any trades" on public.trades
  for delete using (public.is_admin(auth.uid()));

drop policy if exists "admin select all tx" on public.transactions;
create policy "admin select all tx" on public.transactions
  for select using (public.is_admin(auth.uid()));
drop policy if exists "admin delete any tx" on public.transactions;
create policy "admin delete any tx" on public.transactions
  for delete using (public.is_admin(auth.uid()));

drop policy if exists "admin select all playbooks" on public.playbooks;
create policy "admin select all playbooks" on public.playbooks
  for select using (public.is_admin(auth.uid()));
drop policy if exists "admin delete any playbooks" on public.playbooks;
create policy "admin delete any playbooks" on public.playbooks
  for delete using (public.is_admin(auth.uid()));

drop policy if exists "admin delete any ratings" on public.ratings;
create policy "admin delete any ratings" on public.ratings
  for delete using (public.is_admin(auth.uid()));

-- ============================================================
-- 6b. Data-source tracking (where each trade/transaction came from)
alter table public.trades add column if not exists source text default '';
alter table public.transactions add column if not exists source text default '';

-- 7. MAKE YOURSELF ADMIN (edit the email, run after logging in once)
-- ============================================================
update public.profiles set is_admin = true
where email = 'bereketbirhanuassefa@gmail.com';

-- Done. You should see "Success. No rows returned."
