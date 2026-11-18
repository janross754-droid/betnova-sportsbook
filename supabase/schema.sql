-- BETNOVA: secure fixture catalogue foundation
-- Run in the Supabase SQL Editor. This schema is for fictional/sample fixtures only.
-- It creates a non-cash practice wallet only; it does not enable real-money wagering, deposits, withdrawals, or cash payouts.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('admin', 'member')),
  created_at timestamptz not null default now()
);

create or replace function public.handle_new_betnova_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, role)
  values (new.id, 'member')
  on conflict (id) do nothing;

  insert into public.practice_wallets (user_id, balance)
  values (new.id, 1000.00)
  on conflict (user_id) do nothing;

  insert into public.practice_wallet_transactions
    (user_id, transaction_type, amount, description)
  values
    (new.id, 'starter_credit', 1000.00, 'Welcome practice credits — no cash value');
  return new;
end;
$$;

drop trigger if exists on_betnova_auth_user_created on auth.users;
create trigger on_betnova_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_betnova_user();

create or replace function public.is_betnova_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.role = 'admin'
  );
$$;

revoke all on function public.is_betnova_admin() from public, anon;
grant execute on function public.is_betnova_admin() to authenticated;
revoke all on function public.handle_new_betnova_user() from public, anon, authenticated;

create table if not exists public.fixtures (
  id uuid primary key default gen_random_uuid(),
  home_team text not null check (char_length(home_team) between 1 and 80),
  away_team text not null check (char_length(away_team) between 1 and 80),
  competition text not null default 'Sample competition'
    check (char_length(competition) between 1 and 100),
  kickoff_at timestamptz not null,
  status text not null default 'draft'
    check (status in ('draft', 'published', 'cancelled', 'finished')),
  home_score integer check (home_score is null or home_score between 0 and 99),
  away_score integer check (away_score is null or away_score between 0 and 99),
  result_is_illustrative boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint fixtures_different_teams check (lower(home_team) <> lower(away_team)),
  constraint fixtures_scores_paired check (
    (home_score is null and away_score is null)
    or (home_score is not null and away_score is not null)
  )
);

create index if not exists fixtures_public_schedule_idx
  on public.fixtures (kickoff_at)
  where status = 'published';

create or replace function public.set_fixture_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_betnova_fixture_updated_at on public.fixtures;
create trigger set_betnova_fixture_updated_at
  before update on public.fixtures
  for each row execute procedure public.set_fixture_updated_at();

alter table public.profiles enable row level security;
alter table public.fixtures enable row level security;

drop policy if exists "Users can read own profile or admins can read all" on public.profiles;
create policy "Users can read own profile or admins can read all"
  on public.profiles for select to authenticated
  using (id = (select auth.uid()) or (select public.is_betnova_admin()));

drop policy if exists "Public can read published fixtures" on public.fixtures;
create policy "Public can read published fixtures"
  on public.fixtures for select to anon, authenticated
  using (status = 'published');

drop policy if exists "Admins can read all fixtures" on public.fixtures;
create policy "Admins can read all fixtures"
  on public.fixtures for select to authenticated
  using ((select public.is_betnova_admin()));

drop policy if exists "Admins can create fixtures" on public.fixtures;
create policy "Admins can create fixtures"
  on public.fixtures for insert to authenticated
  with check ((select public.is_betnova_admin()));

drop policy if exists "Admins can update fixtures" on public.fixtures;
create policy "Admins can update fixtures"
  on public.fixtures for update to authenticated
  using ((select public.is_betnova_admin()))
  with check ((select public.is_betnova_admin()));

drop policy if exists "Admins can delete fixtures" on public.fixtures;
create policy "Admins can delete fixtures"
  on public.fixtures for delete to authenticated
  using ((select public.is_betnova_admin()));

grant select on public.fixtures to anon, authenticated;
grant insert, update, delete on public.fixtures to authenticated;
grant select on public.profiles to authenticated;

-- After creating your own account, promote ONLY that account to admin by running:
-- update public.profiles
-- set role = 'admin'
-- where id = (select id from auth.users where email = 'YOUR-ADMIN-EMAIL');
--
-- Verify the row before continuing. Never make public sign-up assign admin roles.

-- Per-account non-cash practice wallet. No client-side writes are permitted.
create table if not exists public.practice_wallets (
  user_id uuid primary key references auth.users(id) on delete cascade,
  balance numeric(12,2) not null default 1000.00 check (balance >= 0),
  currency_label text not null default 'PRACTICE CREDITS' check (currency_label = 'PRACTICE CREDITS'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.practice_wallet_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  transaction_type text not null check (transaction_type in ('starter_credit','practice_stake','practice_return','adjustment')),
  amount numeric(12,2) not null check (amount > 0),
  description text not null check (char_length(description) between 1 and 180),
  created_at timestamptz not null default now()
);

create index if not exists practice_wallet_transactions_user_created_idx
  on public.practice_wallet_transactions (user_id, created_at desc);

alter table public.practice_wallets enable row level security;
alter table public.practice_wallet_transactions enable row level security;

drop policy if exists "Users can read own practice wallet" on public.practice_wallets;
create policy "Users can read own practice wallet"
  on public.practice_wallets for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Users can read own practice wallet transactions" on public.practice_wallet_transactions;
create policy "Users can read own practice wallet transactions"
  on public.practice_wallet_transactions for select to authenticated
  using ((select auth.uid()) = user_id);

grant select on public.practice_wallets, public.practice_wallet_transactions to authenticated;

-- Existing accounts receive the same one-time starter practice credits.
insert into public.practice_wallets (user_id, balance)
select u.id, 1000.00 from auth.users u
on conflict (user_id) do nothing;

insert into public.practice_wallet_transactions (user_id, transaction_type, amount, description)
select w.user_id, 'starter_credit', 1000.00, 'Welcome practice credits — no cash value'
from public.practice_wallets w
where not exists (
  select 1 from public.practice_wallet_transactions t
  where t.user_id = w.user_id and t.transaction_type = 'starter_credit'
);
