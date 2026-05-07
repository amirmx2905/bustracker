# bustracker

Don't know if this even works :/ (It does)

## Supabase config

Supabase credentials are loaded at runtime from either:

1. Scheme environment variables (`SUPABASE_URL`, `SUPABASE_KEY`)
2. A bundled `.env` file in the app target

Use `bustracker/bustracker/.env.example` as the template for local setup.

## SQL run order

Run these scripts in order against the Supabase project:

1. `supabase/sql/schema.sql`
2. `supabase/sql/auth_sync.sql`
3. `supabase/sql/functions.sql`

`schema.sql` defines the tables, indexes, RLS, and a server-generated QR code on `students.qr_code` (default `uuid_generate_v4()::text`). `auth_sync.sql` installs the `auth.users` trigger that syncs profile metadata into `public.profiles` on signup. `functions.sql` adds the RPC-backed student write path used by the parent app for registration, QR linking, destination management, and archiving.

## Parent app flow

After the SQL is applied and a parent account is created, the parent home screen can:

1. Register a new student with pickup address and at least one destination — the server generates a unique QR code which the app immediately displays for screenshot/share/print
2. Link an existing student by scanning the QR from a co-parent's phone or pasting the code manually
3. Edit student details and manage destinations
4. Archive a student instead of hard-deleting the record

The driver app will scan the same QR codes to check students in and out (future phase).
