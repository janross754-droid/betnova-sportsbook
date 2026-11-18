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

create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create or replace function private.is_betnova_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid()) and p.role = 'admin'
  );
$$;

revoke all on function private.is_betnova_admin() from public, anon;
grant execute on function private.is_betnova_admin() to authenticated;
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
  using (id = (select auth.uid()) or (select private.is_betnova_admin()));

drop policy if exists "Public can read published fixtures" on public.fixtures;
create policy "Public can read published fixtures"
  on public.fixtures for select to anon, authenticated
  using (status = 'published');

drop policy if exists "Admins can read all fixtures" on public.fixtures;
create policy "Admins can read all fixtures"
  on public.fixtures for select to authenticated
  using ((select private.is_betnova_admin()));

drop policy if exists "Admins can create fixtures" on public.fixtures;
create policy "Admins can create fixtures"
  on public.fixtures for insert to authenticated
  with check ((select private.is_betnova_admin()));

drop policy if exists "Admins can update fixtures" on public.fixtures;
create policy "Admins can update fixtures"
  on public.fixtures for update to authenticated
  using ((select private.is_betnova_admin()))
  with check ((select private.is_betnova_admin()));

drop policy if exists "Admins can delete fixtures" on public.fixtures;
create policy "Admins can delete fixtures"
  on public.fixtures for delete to authenticated
  using ((select private.is_betnova_admin()));

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

 
-- Server-backed practice bet ledger. All balances and bet placement are changed atomically in Postgres.
create table if not exists public.practice_bets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  selections jsonb not null check (jsonb_typeof(selections) = 'array' and jsonb_array_length(selections) between 1 and 20),
  stake numeric(12,2) not null check (stake > 0),
  combined_odds numeric(12,4) not null check (combined_odds > 1),
  potential_return numeric(14,2) not null check (potential_return > 0),
  status text not null default 'open_practice' check (status in ('open_practice','won_practice','lost_practice','void_practice')),
  settled_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists practice_bets_user_created_idx on public.practice_bets(user_id,created_at desc);
alter table public.practice_bets enable row level security;
drop policy if exists "Users read own practice bets" on public.practice_bets;
create policy "Users read own practice bets" on public.practice_bets for select to authenticated using ((select auth.uid()) = user_id);
grant select on public.practice_bets to authenticated;

create or replace function public.place_practice_bet(p_selections jsonb, p_stake numeric, p_combined_odds numeric)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user uuid := (select auth.uid()); v_balance numeric(12,2); v_bet_id uuid; v_return numeric(14,2);
begin
  if v_user is null then raise exception 'Please sign in to place a practice selection.'; end if;
  if jsonb_typeof(p_selections) <> 'array' or jsonb_array_length(p_selections) < 1 or jsonb_array_length(p_selections) > 20 then raise exception 'Your practice slip must contain between 1 and 20 selections.'; end if;
  if p_stake is null or p_stake <= 0 or p_stake > 100000 then raise exception 'Enter a valid practice stake.'; end if;
  if p_combined_odds is null or p_combined_odds <= 1 or p_combined_odds > 100000 then raise exception 'Invalid illustrative odds.'; end if;
  if exists (select 1 from jsonb_array_elements(p_selections) s where coalesce(s->>'fixtureId','')='' or coalesce(s->>'home','')='' or coalesce(s->>'away','')='' or coalesce(s->>'pick','')='' or coalesce((s->>'odds')::numeric,0)<=1) then raise exception 'One or more selections are invalid.'; end if;
  select balance into v_balance from public.practice_wallets where user_id=v_user for update;
  if not found then raise exception 'Practice wallet not found for this account.'; end if;
  if p_stake > v_balance then raise exception 'Your practice stake is greater than your available balance.'; end if;
  v_return := round(p_stake*p_combined_odds,2);
  insert into public.practice_bets(user_id,selections,stake,combined_odds,potential_return) values(v_user,p_selections,p_stake,p_combined_odds,v_return) returning id into v_bet_id;
  update public.practice_wallets set balance=balance-p_stake,updated_at=now() where user_id=v_user;
  insert into public.practice_wallet_transactions(user_id,transaction_type,amount,description) values(v_user,'practice_stake',p_stake,'Practice selection placed · Ref '||left(v_bet_id::text,8));
  return v_bet_id;
end; $$;
revoke all on function public.place_practice_bet(jsonb,numeric,numeric) from public,anon,authenticated;
grant execute on function public.place_practice_bet(jsonb,numeric,numeric) to authenticated;

create or replace function public.settle_practice_bets()
returns integer language plpgsql security definer set search_path = '' as $$
declare v_bet record; v_total integer:=0; v_done integer; v_won boolean;
begin
  if (select auth.uid()) is null or not (select private.is_betnova_admin()) then raise exception 'Administrator access is required to settle practice bets.'; end if;
  for v_bet in select b.id,b.user_id,b.selections,b.potential_return from public.practice_bets b where b.status='open_practice' order by b.created_at for update loop
    select count(*),coalesce(bool_and(case s->>'outcome' when '1' then f.home_score>f.away_score when 'X' then f.home_score=f.away_score when '2' then f.away_score>f.home_score else false end),false)
    into v_done,v_won from jsonb_array_elements(v_bet.selections) s join public.fixtures f on f.id=(s->>'fixtureId')::uuid
    where f.status='finished' and f.result_is_illustrative=true and f.home_score is not null and f.away_score is not null;
    if v_done=jsonb_array_length(v_bet.selections) then
      if v_won then
        update public.practice_bets set status='won_practice',settled_at=now() where id=v_bet.id;
        update public.practice_wallets set balance=balance+v_bet.potential_return,updated_at=now() where user_id=v_bet.user_id;
        insert into public.practice_wallet_transactions(user_id,transaction_type,amount,description) values(v_bet.user_id,'practice_return',v_bet.potential_return,'Practice return · Ref '||left(v_bet.id::text,8));
      else update public.practice_bets set status='lost_practice',settled_at=now() where id=v_bet.id;
      end if;
      v_total:=v_total+1;
    end if;
  end loop;
  return v_total;
end; $$;
revoke all on function public.settle_practice_bets() from public,anon,authenticated;
grant execute on function public.settle_practice_bets() to authenticated;

 
-- Illustrative 1X2 prices configured by an administrator per fixture.
alter table public.fixtures
  add column if not exists home_odds numeric(8,2) not null default 1.85,
  add column if not exists draw_odds numeric(8,2) not null default 3.40,
  add column if not exists away_odds numeric(8,2) not null default 4.20;
do $$
begin
  if not exists (select 1 from pg_constraint where conname='fixtures_home_odds_valid') then alter table public.fixtures add constraint fixtures_home_odds_valid check (home_odds > 1 and home_odds <= 1000); end if;
  if not exists (select 1 from pg_constraint where conname='fixtures_draw_odds_valid') then alter table public.fixtures add constraint fixtures_draw_odds_valid check (draw_odds > 1 and draw_odds <= 1000); end if;
  if not exists (select 1 from pg_constraint where conname='fixtures_away_odds_valid') then alter table public.fixtures add constraint fixtures_away_odds_valid check (away_odds > 1 and away_odds <= 1000); end if;
end $$;
create index if not exists fixtures_created_by_idx on public.fixtures(created_by);
