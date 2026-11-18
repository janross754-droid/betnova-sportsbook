# BETNOVA backend setup

This repository currently hosts a static GitHub Pages front end. The SQL migration in `supabase/schema.sql` prepares a Supabase database for a shared fixture catalogue with row-level security.

## What this foundation does

- Stores fixture records centrally instead of only in one browser's local storage.
- Lets visitors read only fixtures whose status is `published`.
- Restricts creating, editing, and deleting fixtures to authenticated users whose profile role is `admin`.
- Creates every new profile as `member` by default.
- Keeps scores explicitly marked as illustrative by default.

## Setup required before it becomes live

1. Create a Supabase project in your own account.
2. Open **SQL Editor**, paste and run `supabase/schema.sql`.
3. Create your own account using Supabase Authentication.
4. Verify your profile row, then promote only your own account to `admin` using the commented SQL at the bottom of the schema file.
5. Keep the Supabase project URL and publishable/anon key in the public website configuration only. Never put a service-role key, database password, or secret key in HTML, JavaScript, GitHub, or chat.
6. Connect the site to Supabase Auth and the fixtures table, then test public reads and admin-only writes before publishing.

## Important

The current site is not yet connected to this database. Its fixture pages still use browser-local storage until the Supabase project is created and the website integration is configured. Do not treat this as a live admin console.

This backend foundation is limited to fictional/sample fixture listings. It does not implement real-money betting, odds trading, payments, deposits, withdrawals, payouts, or a cash wallet. Those features must remain disabled unless the required Ghanaian regulatory approvals, legal advice, and secure operational controls are in place.
