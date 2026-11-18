# BETNOVA backend setup

This repository currently hosts a static GitHub Pages front end. The SQL migration in `supabase/schema.sql` prepares a Supabase database for a shared fixture catalogue with row-level security.

## What this foundation does

- Stores fixture records centrally instead of only in one browser's local storage.
- Lets visitors read only fixtures whose status is `published`.
- Restricts creating, editing, and deleting fixtures to authenticated users whose profile role is `admin`.
- Creates every new profile as `member` by default.
- Keeps scores explicitly marked as illustrative by default.
- Creates a private per-account practice wallet with 1,000 non-cash starter credits.
- Shows the member's practice balance and wallet activity in `wallet.html`.
- Restricts wallet reads to the signed-in owner; the browser cannot edit balances or transaction records.

## Setup required before it becomes live

1. Create a Supabase project in your own account.
2. Open **SQL Editor**, paste and run `supabase/schema.sql`.
3. Create your own account using Supabase Authentication.
4. Verify your profile row, then promote only your own account to `admin` using the commented SQL at the bottom of the schema file.
5. Keep the Supabase project URL and publishable/anon key in the public website configuration only. Never put a service-role key, database password, or secret key in HTML, JavaScript, GitHub, or chat.
6. Connect the site to Supabase Auth and the fixtures table, then test public reads and admin-only writes before publishing.

## Important

The current site is not yet connected to this database. Its fixture pages still use browser-local storage until the Supabase project is created and the website integration is configured. Do not treat this as a live admin console.

The wallet is a practice-credit ledger only. It is not denominated in Ghana cedis, has no cash value, and cannot accept deposits, real-money stakes, payouts, transfers, or withdrawals. Payment controls are intentionally disabled. Do not add real-money payment processing or wagering without the applicable legal approvals and a separately reviewed, secure payment and ledger architecture.
