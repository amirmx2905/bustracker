# bustracker

Don't know if this even works :/ (It does)

## Supabase config

Supabase credentials are loaded at runtime from either:

1. Scheme environment variables (`SUPABASE_URL`, `SUPABASE_KEY`)
2. A bundled `.env` file in the app target

Use `bustracker/bustracker/.env.example` as the template for local setup.

## SQL run order

Run these scripts in order against the Supabase project:

1. `supabase/sql/phase2_schema.sql`
2. `supabase/sql/phase2_auth_profile_sync.sql`
3. `supabase/sql/phase3_students_and_relationships.sql`

The phase 3 script adds the RPC-backed student write path used by the parent app flow for student registration, NFC linking, destination management, and archive behavior.
If phase 3 was already applied before the duplicate-hardening changes, rerun `supabase/sql/phase3_students_and_relationships.sql` to install the new student-identity and destination uniqueness guards.

## Phase 3 app flow

After the SQL is applied and a parent account is created in the app, the parent home screen can:

1. Register a new student with an NFC tag, pickup address, and at least one destination
2. Link an existing student by scanning or entering the student's NFC UID
3. Edit student details and manage destinations
4. Archive a student instead of hard-deleting the record
