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

-- Done. You should see "Success. No rows returned."
