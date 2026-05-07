-- BusTracker schema. Run this first, then auth_sync.sql, then functions.sql.
--
-- Student identity uses a server-generated QR code (uuid_generate_v4()::text) that the
-- parent app renders as a QR image. The driver app will scan it to check students in/out.
-- Parents never type or scan it during registration.

create extension if not exists postgis;
create extension if not exists "uuid-ossp";

-- Enums

do $$
begin
    create type public.user_role as enum ('parent', 'driver');
exception
    when duplicate_object then null;
end
$$;

do $$
begin
    create type public.event_type as enum (
        'check_in',
        'check_out',
        'destination_enter',
        'destination_exit',
        'pickup_proximity',
        'unknown_scan'
    );
exception
    when duplicate_object then null;
end
$$;

do $$
begin
    create type public.notification_kind as enum (
        'boarded',
        'arrived_destination',
        'descended_destination',
        'left_destination',
        'near_pickup',
        'descended_pickup'
    );
exception
    when duplicate_object then null;
end
$$;

do $$
begin
    create type public.delivery_status as enum ('pending', 'delivered', 'failed');
exception
    when duplicate_object then null;
end
$$;

-- Profiles (extends auth.users)
-- Profiles hold identity only. Pickup is a property of the student, not the parent —
-- see students.pickup_point. This avoids duplicating the same address across multiple
-- students at the same home and across co-parents.
create table if not exists public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    role public.user_role not null,
    full_name text not null,
    created_at timestamptz not null default now()
);

-- Students
-- qr_code is generated server-side on insert; the parent app displays it as a QR image
-- for the driver to scan and for co-parent linking. It is never client-supplied.
create table if not exists public.students (
    id uuid primary key default uuid_generate_v4(),
    qr_code text not null default uuid_generate_v4()::text,
    full_name text not null,
    date_of_birth date not null,
    pickup_point geography(point, 4326) not null,
    pickup_address text not null,
    active boolean not null default true,
    created_at timestamptz not null default now()
);
create unique index if not exists students_qr_code_active_unique
    on public.students (qr_code)
    where active;
create index if not exists students_pickup_gix on public.students using gist (pickup_point);
create unique index if not exists students_identity_active_unique
    on public.students ((lower(btrim(full_name))), date_of_birth)
    where active;

-- Student ↔ Parent (multi-tutor)
create table if not exists public.student_parents (
    student_id uuid not null references public.students(id) on delete cascade,
    parent_id uuid not null references public.profiles(id) on delete cascade,
    is_registrar boolean not null default false,
    linked_at timestamptz not null default now(),
    primary key (student_id, parent_id)
);
create unique index if not exists one_registrar_per_student
    on public.student_parents (student_id)
    where is_registrar;
create index if not exists student_parents_by_parent on public.student_parents (parent_id);

-- Destinations
create table if not exists public.destinations (
    id uuid primary key default uuid_generate_v4(),
    student_id uuid not null references public.students(id) on delete cascade,
    label text not null,
    point geography(point, 4326) not null,
    address text not null,
    created_at timestamptz not null default now()
);
create index if not exists destinations_by_student on public.destinations (student_id);
create index if not exists destinations_gix on public.destinations using gist (point);
create unique index if not exists destinations_student_label_address_unique
    on public.destinations (student_id, (lower(btrim(label))), (lower(btrim(address))));

-- Trips
create table if not exists public.trips (
    id uuid primary key default uuid_generate_v4(),
    driver_id uuid not null references public.profiles(id),
    started_at timestamptz not null default now(),
    ended_at timestamptz
);
create unique index if not exists one_active_trip_per_driver
    on public.trips (driver_id)
    where ended_at is null;
create index if not exists trips_by_driver on public.trips (driver_id, started_at desc);

-- GPS positions
create table if not exists public.trip_positions (
    id bigserial primary key,
    trip_id uuid not null references public.trips(id) on delete cascade,
    point geography(point, 4326) not null,
    recorded_at timestamptz not null default now()
);
create index if not exists trip_positions_by_trip_time
    on public.trip_positions (trip_id, recorded_at desc);
create index if not exists trip_positions_gix on public.trip_positions using gist (point);

-- GPS gaps
create table if not exists public.gps_gaps (
    id bigserial primary key,
    trip_id uuid not null references public.trips(id) on delete cascade,
    gap_start timestamptz not null,
    gap_end timestamptz
);

-- Events
-- raw_qr_payload captures the raw scanned string when it does not resolve to a known active
-- student (event_type = 'unknown_scan'). For successful scans, student_id is set.
create table if not exists public.events (
    id uuid primary key default uuid_generate_v4(),
    trip_id uuid not null references public.trips(id) on delete cascade,
    type public.event_type not null,
    student_id uuid references public.students(id) on delete set null,
    destination_id uuid references public.destinations(id) on delete set null,
    parent_id uuid references public.profiles(id) on delete set null,
    point geography(point, 4326),
    raw_qr_payload text,
    occurred_at timestamptz not null default now()
);
create index if not exists events_by_trip_time on public.events (trip_id, occurred_at);
create index if not exists events_by_student_time
    on public.events (student_id, occurred_at desc);
create unique index if not exists dest_enter_once_per_student
    on public.events (trip_id, student_id, destination_id)
    where type = 'destination_enter';
create unique index if not exists pickup_prox_once_per_parent
    on public.events (trip_id, parent_id)
    where type = 'pickup_proximity';

-- Notifications
create table if not exists public.notifications (
    id uuid primary key default uuid_generate_v4(),
    event_id uuid not null references public.events(id) on delete cascade,
    parent_id uuid not null references public.profiles(id) on delete cascade,
    student_id uuid not null references public.students(id) on delete cascade,
    kind public.notification_kind not null,
    payload jsonb not null,
    status public.delivery_status not null default 'pending',
    attempts int not null default 0,
    created_at timestamptz not null default now(),
    delivered_at timestamptz
);
create index if not exists notifications_by_parent_time
    on public.notifications (parent_id, created_at desc);
create index if not exists notifications_by_student_time
    on public.notifications (student_id, created_at desc);

-- Per-parent history soft delete
create table if not exists public.history_deletions (
    parent_id uuid not null references public.profiles(id) on delete cascade,
    event_id uuid not null references public.events(id) on delete cascade,
    deleted_at timestamptz not null default now(),
    primary key (parent_id, event_id)
);

-- APNs tokens
create table if not exists public.device_tokens (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid not null references public.profiles(id) on delete cascade,
    apns_token text not null unique,
    updated_at timestamptz not null default now()
);

-- Private helper schema (RLS predicates and security-definer functions live here).
-- "Private" here means PostgREST does not expose it as a REST surface — authenticated
-- still needs USAGE so RLS policies and SQL-language wrappers in `public` can call into it.
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;
grant usage on schema private to service_role;

create or replace function private.is_parent_of(target_student uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1
        from public.student_parents
        where student_id = target_student
          and parent_id = auth.uid()
    );
$$;

revoke all on function private.is_parent_of(uuid) from public;
grant execute on function private.is_parent_of(uuid) to authenticated;
grant execute on function private.is_parent_of(uuid) to service_role;

-- RLS

alter table public.profiles enable row level security;
alter table public.students enable row level security;
alter table public.student_parents enable row level security;
alter table public.destinations enable row level security;
alter table public.trips enable row level security;
alter table public.trip_positions enable row level security;
alter table public.gps_gaps enable row level security;
alter table public.events enable row level security;
alter table public.notifications enable row level security;
alter table public.history_deletions enable row level security;
alter table public.device_tokens enable row level security;

drop policy if exists "own profile" on public.profiles;
create policy "own profile"
    on public.profiles
    for select
    using (id = auth.uid());

drop policy if exists "update own profile" on public.profiles;
create policy "update own profile"
    on public.profiles
    for update
    using (id = auth.uid())
    with check (
        id = auth.uid()
        and role = (
            select current_profile.role
            from public.profiles as current_profile
            where current_profile.id = auth.uid()
        )
    );

drop policy if exists "insert own profile" on public.profiles;
create policy "insert own profile"
    on public.profiles
    for insert
    with check (id = auth.uid());

drop policy if exists "students for linked parents" on public.students;
create policy "students for linked parents"
    on public.students
    for select
    using (private.is_parent_of(id));

drop policy if exists "own links" on public.student_parents;
create policy "own links"
    on public.student_parents
    for select
    using (parent_id = auth.uid());

drop policy if exists "destinations for linked parents" on public.destinations;
create policy "destinations for linked parents"
    on public.destinations
    for select
    using (private.is_parent_of(student_id));

drop policy if exists "driver own trips" on public.trips;
create policy "driver own trips"
    on public.trips
    for all
    using (driver_id = auth.uid())
    with check (driver_id = auth.uid());

drop policy if exists "parent sees relevant trips" on public.trips;
create policy "parent sees relevant trips"
    on public.trips
    for select
    using (
        exists (
            select 1
            from public.events e
            join public.student_parents sp on sp.student_id = e.student_id
            where e.trip_id = trips.id
              and sp.parent_id = auth.uid()
              and e.type = 'check_in'
              and not exists (
                  select 1
                  from public.events e2
                  where e2.trip_id = e.trip_id
                    and e2.student_id = e.student_id
                    and e2.type = 'check_out'
                    and e2.occurred_at > e.occurred_at
              )
        )
    );

drop policy if exists "driver writes own positions" on public.trip_positions;
create policy "driver writes own positions"
    on public.trip_positions
    for insert
    with check (
        exists (
            select 1
            from public.trips t
            where t.id = trip_id and t.driver_id = auth.uid()
        )
    );

drop policy if exists "parent reads positions while child onboard" on public.trip_positions;
create policy "parent reads positions while child onboard"
    on public.trip_positions
    for select
    using (
        exists (
            select 1
            from public.events e
            join public.student_parents sp on sp.student_id = e.student_id
            where e.trip_id = trip_positions.trip_id
              and sp.parent_id = auth.uid()
              and e.type = 'check_in'
              and not exists (
                  select 1
                  from public.events e2
                  where e2.trip_id = e.trip_id
                    and e2.student_id = e.student_id
                    and e2.type = 'check_out'
                    and e2.occurred_at > e.occurred_at
              )
        )
    );

drop policy if exists "driver sees own trip events" on public.events;
create policy "driver sees own trip events"
    on public.events
    for select
    using (
        exists (
            select 1
            from public.trips t
            where t.id = trip_id and t.driver_id = auth.uid()
        )
    );

drop policy if exists "parent sees own students events" on public.events;
create policy "parent sees own students events"
    on public.events
    for select
    using (
        student_id is not null
        and private.is_parent_of(student_id)
        and not exists (
            select 1
            from public.history_deletions hd
            where hd.parent_id = auth.uid() and hd.event_id = events.id
        )
    );

drop policy if exists "own notifications" on public.notifications;
create policy "own notifications"
    on public.notifications
    for select
    using (parent_id = auth.uid());

drop policy if exists "own deletions" on public.history_deletions;
create policy "own deletions"
    on public.history_deletions
    for all
    using (parent_id = auth.uid())
    with check (parent_id = auth.uid());

drop policy if exists "own device tokens" on public.device_tokens;
create policy "own device tokens"
    on public.device_tokens
    for all
    using (user_id = auth.uid())
    with check (user_id = auth.uid());

-- Grants
-- Grants and RLS are independent gates: a request must satisfy BOTH the table grant
-- and the row-level policy. Mismatch is the most common source of "permission denied"
-- errors, so keep them aligned with the policy intent above.
grant usage on schema public to authenticated;
grant usage on schema public to service_role;

-- Authenticated table grants
-- - profiles: client inserts via "repair" path on first sign-in; updates on profile edit
-- - students / student_parents / destinations: writes go through public.* RPCs (security
--   definer), so authenticated only needs SELECT here
-- - trips: driver app starts and ends trips directly (RLS gates ownership)
-- - trip_positions: driver pushes GPS pings directly (RLS gates ownership)
-- - events / notifications: writes happen via RPCs or service_role; client only reads
-- - history_deletions / device_tokens: per-parent ownership, full direct CRUD
grant select, insert, update on table public.profiles to authenticated;
grant select on table public.students to authenticated;
grant select on table public.student_parents to authenticated;
grant select on table public.destinations to authenticated;
grant select, insert, update on table public.trips to authenticated;
grant select, insert on table public.trip_positions to authenticated;
grant select on table public.events to authenticated;
grant select on table public.notifications to authenticated;
grant select, insert, delete on table public.history_deletions to authenticated;
grant select, insert, update, delete on table public.device_tokens to authenticated;

-- service_role bypasses RLS; full CRUD on every public table.
grant select, insert, update, delete on table public.profiles to service_role;
grant select, insert, update, delete on table public.students to service_role;
grant select, insert, update, delete on table public.student_parents to service_role;
grant select, insert, update, delete on table public.destinations to service_role;
grant select, insert, update, delete on table public.trips to service_role;
grant select, insert, update, delete on table public.trip_positions to service_role;
grant select, insert, update, delete on table public.gps_gaps to service_role;
grant select, insert, update, delete on table public.events to service_role;
grant select, insert, update, delete on table public.notifications to service_role;
grant select, insert, update, delete on table public.history_deletions to service_role;
grant select, insert, update, delete on table public.device_tokens to service_role;

-- Sequences (bigserial columns). Without USAGE on the underlying sequence, INSERTs
-- on trip_positions and gps_gaps fail even when the table grant is correct.
grant usage, select on all sequences in schema public to authenticated;
grant usage, select on all sequences in schema public to service_role;

-- Default privileges for any tables/sequences created later (future phases) so we don't
-- have to remember to re-grant. Owner here is the role running this script (postgres in
-- Supabase). These only affect objects created by that same role going forward.
alter default privileges in schema public
    grant select on tables to authenticated;
alter default privileges in schema public
    grant select, insert, update, delete on tables to service_role;
alter default privileges in schema public
    grant usage, select on sequences to authenticated;
alter default privileges in schema public
    grant usage, select on sequences to service_role;
