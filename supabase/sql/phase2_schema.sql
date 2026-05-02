create extension if not exists postgis;
create extension if not exists "uuid-ossp";

-- Keep auth.users trigger DDL out of this file.
-- Running auth trigger creation in the same SQL batch as public table/policy DDL can
-- deadlock under live signup traffic because Postgres keeps those DDL locks until the
-- batch commits. Install profile sync afterward with supabase/sql/phase2_auth_profile_sync.sql.

do $$
begin
    create type public.user_role as enum ('parent', 'driver');
exception
    when duplicate_object then null;
end
$$;

create table if not exists public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    role public.user_role not null,
    full_name text not null,
    pickup_label text,
    pickup_point geography(point, 4326),
    pickup_address text,
    created_at timestamptz not null default now(),
    constraint parent_has_pickup check (
        role <> 'parent' or (pickup_point is not null and pickup_address is not null)
    )
);

create index if not exists profiles_pickup_gix on public.profiles using gist (pickup_point);

create table if not exists public.students (
    id uuid primary key default uuid_generate_v4(),
    nfc_uid text not null,
    full_name text not null,
    date_of_birth date not null,
    pickup_point geography(point, 4326) not null,
    pickup_address text not null,
    active boolean not null default true,
    created_at timestamptz not null default now()
);

create unique index if not exists students_nfc_uid_active_unique
    on public.students (nfc_uid)
    where active;

create index if not exists students_pickup_gix on public.students using gist (pickup_point);

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

create schema if not exists private;
revoke all on schema private from public;

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

alter table public.profiles enable row level security;
alter table public.students enable row level security;
alter table public.student_parents enable row level security;
alter table public.destinations enable row level security;

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

drop policy if exists "delete own profile" on public.profiles;

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

grant usage on schema public to authenticated;
grant select, insert, update on table public.profiles to authenticated;
grant select on table public.students to authenticated;
grant select on table public.student_parents to authenticated;
grant select on table public.destinations to authenticated;
