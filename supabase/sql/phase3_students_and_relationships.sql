-- Run after supabase/sql/phase2_schema.sql and supabase/sql/phase2_auth_profile_sync.sql.
-- This script adds the Phase 3 write path for students, parent links, and destinations.
-- All mutating operations go through RPC wrappers so multi-table validation stays atomic.

create schema if not exists private;
revoke all on schema private from public;

create or replace function private.normalize_nfc_uid(raw_uid text)
returns text
language sql
immutable
as $$
    select nullif(upper(btrim(raw_uid)), '');
$$;

create or replace function private.require_parent_profile()
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    current_user_id uuid := auth.uid();
    current_role public.user_role;
begin
    if current_user_id is null then
        raise exception 'Authentication required.';
    end if;

    select p.role
    into current_role
    from public.profiles as p
    where p.id = current_user_id;

    if current_role is null then
        raise exception 'Your profile is missing.';
    end if;

    if current_role <> 'parent' then
        raise exception 'Only parent accounts can manage students.';
    end if;

    return current_user_id;
end;
$$;

create or replace function private.require_linked_parent(target_student_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    current_parent_id uuid := private.require_parent_profile();
begin
    if not exists (
        select 1
        from public.student_parents
        where student_id = target_student_id
          and parent_id = current_parent_id
    ) then
        raise exception 'You are not linked to this student.';
    end if;

    return current_parent_id;
end;
$$;

create unique index if not exists students_identity_active_unique
    on public.students ((lower(btrim(full_name))), date_of_birth)
    where active;

create unique index if not exists destinations_student_label_address_unique
    on public.destinations (student_id, (lower(btrim(label))), (lower(btrim(address))));

create or replace function private.student_duplicate_exists(
    student_full_name text,
    student_date_of_birth date,
    exclude_student_id uuid default null
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1
        from public.students
        where active
          and lower(btrim(full_name)) = lower(btrim(student_full_name))
          and date_of_birth = student_date_of_birth
          and (exclude_student_id is null or id <> exclude_student_id)
    );
$$;

create or replace function private.create_student_with_destination_impl(
    student_nfc_uid text,
    student_full_name text,
    student_date_of_birth date,
    student_pickup_address text,
    student_pickup_lat double precision,
    student_pickup_lng double precision,
    destination_label text,
    destination_address text,
    destination_lat double precision,
    destination_lng double precision
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    current_parent_id uuid := private.require_parent_profile();
    normalized_nfc_uid text := private.normalize_nfc_uid(student_nfc_uid);
    trimmed_full_name text := nullif(btrim(student_full_name), '');
    trimmed_pickup_address text := nullif(btrim(student_pickup_address), '');
    trimmed_destination_label text := nullif(btrim(destination_label), '');
    trimmed_destination_address text := nullif(btrim(destination_address), '');
    created_student_id uuid;
begin
    if normalized_nfc_uid is null then
        raise exception 'Scan an NFC tag before saving the student.';
    end if;

    if trimmed_full_name is null then
        raise exception 'Student name is required.';
    end if;

    if student_date_of_birth is null then
        raise exception 'Date of birth is required.';
    end if;

    if trimmed_pickup_address is null then
        raise exception 'Pickup address is required.';
    end if;

    if student_pickup_lat is null or student_pickup_lng is null then
        raise exception 'Pickup address must be geocoded before saving.';
    end if;

    if trimmed_destination_label is null or trimmed_destination_address is null then
        raise exception 'At least one destination is required.';
    end if;

    if destination_lat is null or destination_lng is null then
        raise exception 'Destination address must be geocoded before saving.';
    end if;

    if private.student_duplicate_exists(trimmed_full_name, student_date_of_birth) then
        raise exception 'An active student with the same name and date of birth already exists.';
    end if;

    if exists (
        select 1
        from public.students
        where nfc_uid = normalized_nfc_uid
          and active
    ) then
        raise exception 'This NFC tag is already linked to another active student.';
    end if;

    insert into public.students (
        nfc_uid,
        full_name,
        date_of_birth,
        pickup_point,
        pickup_address,
        active
    )
    values (
        normalized_nfc_uid,
        trimmed_full_name,
        student_date_of_birth,
        ST_SetSRID(ST_MakePoint(student_pickup_lng, student_pickup_lat), 4326)::geography,
        trimmed_pickup_address,
        true
    )
    returning id into created_student_id;

    insert into public.student_parents (student_id, parent_id, is_registrar)
    values (created_student_id, current_parent_id, true);

    insert into public.destinations (
        student_id,
        label,
        point,
        address
    )
    values (
        created_student_id,
        trimmed_destination_label,
        ST_SetSRID(ST_MakePoint(destination_lng, destination_lat), 4326)::geography,
        trimmed_destination_address
    );

    return created_student_id;
exception
    when unique_violation then
        if exists (
            select 1
            from public.students
            where nfc_uid = normalized_nfc_uid
              and active
        ) then
            raise exception 'This NFC tag is already linked to another active student.';
        end if;
        if private.student_duplicate_exists(trimmed_full_name, student_date_of_birth) then
            raise exception 'An active student with the same name and date of birth already exists.';
        end if;
        raise;
end;
$$;

create or replace function private.update_student_impl(
    target_student_id uuid,
    student_nfc_uid text,
    student_full_name text,
    student_date_of_birth date,
    student_pickup_address text,
    student_pickup_lat double precision,
    student_pickup_lng double precision
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    normalized_nfc_uid text := private.normalize_nfc_uid(student_nfc_uid);
    trimmed_full_name text := nullif(btrim(student_full_name), '');
    trimmed_pickup_address text := nullif(btrim(student_pickup_address), '');
begin
    perform private.require_linked_parent(target_student_id);

    if normalized_nfc_uid is null then
        raise exception 'Scan an NFC tag before saving the student.';
    end if;

    if trimmed_full_name is null then
        raise exception 'Student name is required.';
    end if;

    if student_date_of_birth is null then
        raise exception 'Date of birth is required.';
    end if;

    if trimmed_pickup_address is null then
        raise exception 'Pickup address is required.';
    end if;

    if student_pickup_lat is null or student_pickup_lng is null then
        raise exception 'Pickup address must be geocoded before saving.';
    end if;

    if private.student_duplicate_exists(trimmed_full_name, student_date_of_birth, target_student_id) then
        raise exception 'An active student with the same name and date of birth already exists.';
    end if;

    perform 1
    from public.students
    where id = target_student_id
    for update;

    if not found then
        raise exception 'Student not found.';
    end if;

    update public.students
    set
        nfc_uid = normalized_nfc_uid,
        full_name = trimmed_full_name,
        date_of_birth = student_date_of_birth,
        pickup_point = ST_SetSRID(ST_MakePoint(student_pickup_lng, student_pickup_lat), 4326)::geography,
        pickup_address = trimmed_pickup_address
    where id = target_student_id;
exception
    when unique_violation then
        if private.student_duplicate_exists(trimmed_full_name, student_date_of_birth, target_student_id) then
            raise exception 'An active student with the same name and date of birth already exists.';
        end if;
        raise exception 'This NFC tag is already linked to another active student.';
end;
$$;

create or replace function private.archive_student_impl(target_student_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    perform private.require_linked_parent(target_student_id);

    update public.students
    set active = false
    where id = target_student_id;

    if not found then
        raise exception 'Student not found.';
    end if;
end;
$$;

create or replace function private.link_student_by_nfc_impl(student_nfc_uid text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    current_parent_id uuid := private.require_parent_profile();
    normalized_nfc_uid text := private.normalize_nfc_uid(student_nfc_uid);
    target_student_id uuid;
begin
    if normalized_nfc_uid is null then
        raise exception 'Scan an NFC tag before linking a student.';
    end if;

    select s.id
    into target_student_id
    from public.students as s
    where s.nfc_uid = normalized_nfc_uid
      and s.active
    limit 1;

    if target_student_id is null then
        raise exception 'No active student matches that NFC tag.';
    end if;

    insert into public.student_parents (student_id, parent_id, is_registrar)
    values (target_student_id, current_parent_id, false)
    on conflict (student_id, parent_id) do update
    set linked_at = now();

    return target_student_id;
end;
$$;

create or replace function private.add_destination_impl(
    target_student_id uuid,
    destination_label text,
    destination_address text,
    destination_lat double precision,
    destination_lng double precision
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    trimmed_destination_label text := nullif(btrim(destination_label), '');
    trimmed_destination_address text := nullif(btrim(destination_address), '');
    created_destination_id uuid;
begin
    perform private.require_linked_parent(target_student_id);

    if trimmed_destination_label is null or trimmed_destination_address is null then
        raise exception 'Destination label and address are required.';
    end if;

    if destination_lat is null or destination_lng is null then
        raise exception 'Destination address must be geocoded before saving.';
    end if;

    if exists (
        select 1
        from public.destinations
        where student_id = target_student_id
          and lower(btrim(label)) = lower(btrim(trimmed_destination_label))
          and lower(btrim(address)) = lower(btrim(trimmed_destination_address))
    ) then
        raise exception 'This student already has that destination.';
    end if;

    insert into public.destinations (
        student_id,
        label,
        point,
        address
    )
    values (
        target_student_id,
        trimmed_destination_label,
        ST_SetSRID(ST_MakePoint(destination_lng, destination_lat), 4326)::geography,
        trimmed_destination_address
    )
    returning id into created_destination_id;

    return created_destination_id;
exception
    when unique_violation then
        raise exception 'This student already has that destination.';
end;
$$;

create or replace function private.update_destination_impl(
    target_destination_id uuid,
    destination_label text,
    destination_address text,
    destination_lat double precision,
    destination_lng double precision
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    target_student_id uuid;
    trimmed_destination_label text := nullif(btrim(destination_label), '');
    trimmed_destination_address text := nullif(btrim(destination_address), '');
begin
    select d.student_id
    into target_student_id
    from public.destinations as d
    where d.id = target_destination_id;

    if target_student_id is null then
        raise exception 'Destination not found.';
    end if;

    perform private.require_linked_parent(target_student_id);

    if trimmed_destination_label is null or trimmed_destination_address is null then
        raise exception 'Destination label and address are required.';
    end if;

    if destination_lat is null or destination_lng is null then
        raise exception 'Destination address must be geocoded before saving.';
    end if;

    if exists (
        select 1
        from public.destinations
        where student_id = target_student_id
          and id <> target_destination_id
          and lower(btrim(label)) = lower(btrim(trimmed_destination_label))
          and lower(btrim(address)) = lower(btrim(trimmed_destination_address))
    ) then
        raise exception 'This student already has that destination.';
    end if;

    update public.destinations
    set
        label = trimmed_destination_label,
        point = ST_SetSRID(ST_MakePoint(destination_lng, destination_lat), 4326)::geography,
        address = trimmed_destination_address
    where id = target_destination_id;
exception
    when unique_violation then
        raise exception 'This student already has that destination.';
end;
$$;

create or replace function private.delete_destination_impl(target_destination_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    target_student_id uuid;
    destination_count bigint;
begin
    select d.student_id
    into target_student_id
    from public.destinations as d
    where d.id = target_destination_id
    for update;

    if target_student_id is null then
        raise exception 'Destination not found.';
    end if;

    perform private.require_linked_parent(target_student_id);

    perform 1
    from public.students
    where id = target_student_id
    for update;

    select count(*)
    into destination_count
    from public.destinations
    where student_id = target_student_id;

    if destination_count <= 1 then
        raise exception 'Students must keep at least one destination.';
    end if;

    delete from public.destinations
    where id = target_destination_id;
end;
$$;

revoke all on function private.normalize_nfc_uid(text) from public;
revoke all on function private.require_parent_profile() from public;
revoke all on function private.require_linked_parent(uuid) from public;
revoke all on function private.student_duplicate_exists(text, date, uuid) from public;
revoke all on function private.create_student_with_destination_impl(text, text, date, text, double precision, double precision, text, text, double precision, double precision) from public;
revoke all on function private.update_student_impl(uuid, text, text, date, text, double precision, double precision) from public;
revoke all on function private.archive_student_impl(uuid) from public;
revoke all on function private.link_student_by_nfc_impl(text) from public;
revoke all on function private.add_destination_impl(uuid, text, text, double precision, double precision) from public;
revoke all on function private.update_destination_impl(uuid, text, text, double precision, double precision) from public;
revoke all on function private.delete_destination_impl(uuid) from public;

grant execute on function private.normalize_nfc_uid(text) to authenticated;
grant execute on function private.require_parent_profile() to authenticated;
grant execute on function private.require_linked_parent(uuid) to authenticated;
grant execute on function private.student_duplicate_exists(text, date, uuid) to authenticated;
grant execute on function private.create_student_with_destination_impl(text, text, date, text, double precision, double precision, text, text, double precision, double precision) to authenticated;
grant execute on function private.update_student_impl(uuid, text, text, date, text, double precision, double precision) to authenticated;
grant execute on function private.archive_student_impl(uuid) to authenticated;
grant execute on function private.link_student_by_nfc_impl(text) to authenticated;
grant execute on function private.add_destination_impl(uuid, text, text, double precision, double precision) to authenticated;
grant execute on function private.update_destination_impl(uuid, text, text, double precision, double precision) to authenticated;
grant execute on function private.delete_destination_impl(uuid) to authenticated;
grant execute on function private.normalize_nfc_uid(text) to service_role;
grant execute on function private.require_parent_profile() to service_role;
grant execute on function private.require_linked_parent(uuid) to service_role;
grant execute on function private.student_duplicate_exists(text, date, uuid) to service_role;
grant execute on function private.create_student_with_destination_impl(text, text, date, text, double precision, double precision, text, text, double precision, double precision) to service_role;
grant execute on function private.update_student_impl(uuid, text, text, date, text, double precision, double precision) to service_role;
grant execute on function private.archive_student_impl(uuid) to service_role;
grant execute on function private.link_student_by_nfc_impl(text) to service_role;
grant execute on function private.add_destination_impl(uuid, text, text, double precision, double precision) to service_role;
grant execute on function private.update_destination_impl(uuid, text, text, double precision, double precision) to service_role;
grant execute on function private.delete_destination_impl(uuid) to service_role;

create or replace function public.create_student_with_destination(
    student_nfc_uid text,
    student_full_name text,
    student_date_of_birth date,
    student_pickup_address text,
    student_pickup_lat double precision,
    student_pickup_lng double precision,
    destination_label text,
    destination_address text,
    destination_lat double precision,
    destination_lng double precision
)
returns uuid
language sql
set search_path = public
as $$
    select private.create_student_with_destination_impl(
        student_nfc_uid,
        student_full_name,
        student_date_of_birth,
        student_pickup_address,
        student_pickup_lat,
        student_pickup_lng,
        destination_label,
        destination_address,
        destination_lat,
        destination_lng
    );
$$;

create or replace function public.update_student(
    target_student_id uuid,
    student_nfc_uid text,
    student_full_name text,
    student_date_of_birth date,
    student_pickup_address text,
    student_pickup_lat double precision,
    student_pickup_lng double precision
)
returns void
language sql
set search_path = public
as $$
    select private.update_student_impl(
        target_student_id,
        student_nfc_uid,
        student_full_name,
        student_date_of_birth,
        student_pickup_address,
        student_pickup_lat,
        student_pickup_lng
    );
$$;

create or replace function public.archive_student(target_student_id uuid)
returns void
language sql
set search_path = public
as $$
    select private.archive_student_impl(target_student_id);
$$;

create or replace function public.student_duplicate_exists(
    student_full_name text,
    student_date_of_birth date,
    exclude_student_id uuid default null
)
returns boolean
language sql
set search_path = public
as $$
    select private.student_duplicate_exists(
        student_full_name,
        student_date_of_birth,
        exclude_student_id
    );
$$;

create or replace function public.link_student_by_nfc(student_nfc_uid text)
returns uuid
language sql
set search_path = public
as $$
    select private.link_student_by_nfc_impl(student_nfc_uid);
$$;

create or replace function public.add_destination(
    target_student_id uuid,
    destination_label text,
    destination_address text,
    destination_lat double precision,
    destination_lng double precision
)
returns uuid
language sql
set search_path = public
as $$
    select private.add_destination_impl(
        target_student_id,
        destination_label,
        destination_address,
        destination_lat,
        destination_lng
    );
$$;

create or replace function public.update_destination(
    target_destination_id uuid,
    destination_label text,
    destination_address text,
    destination_lat double precision,
    destination_lng double precision
)
returns void
language sql
set search_path = public
as $$
    select private.update_destination_impl(
        target_destination_id,
        destination_label,
        destination_address,
        destination_lat,
        destination_lng
    );
$$;

create or replace function public.delete_destination(target_destination_id uuid)
returns void
language sql
set search_path = public
as $$
    select private.delete_destination_impl(target_destination_id);
$$;

revoke all on function public.create_student_with_destination(text, text, date, text, double precision, double precision, text, text, double precision, double precision) from public;
revoke all on function public.update_student(uuid, text, text, date, text, double precision, double precision) from public;
revoke all on function public.archive_student(uuid) from public;
revoke all on function public.student_duplicate_exists(text, date, uuid) from public;
revoke all on function public.link_student_by_nfc(text) from public;
revoke all on function public.add_destination(uuid, text, text, double precision, double precision) from public;
revoke all on function public.update_destination(uuid, text, text, double precision, double precision) from public;
revoke all on function public.delete_destination(uuid) from public;

grant execute on function public.create_student_with_destination(text, text, date, text, double precision, double precision, text, text, double precision, double precision) to authenticated;
grant execute on function public.update_student(uuid, text, text, date, text, double precision, double precision) to authenticated;
grant execute on function public.archive_student(uuid) to authenticated;
grant execute on function public.student_duplicate_exists(text, date, uuid) to authenticated;
grant execute on function public.link_student_by_nfc(text) to authenticated;
grant execute on function public.add_destination(uuid, text, text, double precision, double precision) to authenticated;
grant execute on function public.update_destination(uuid, text, text, double precision, double precision) to authenticated;
grant execute on function public.delete_destination(uuid) to authenticated;
grant execute on function public.create_student_with_destination(text, text, date, text, double precision, double precision, text, text, double precision, double precision) to service_role;
grant execute on function public.update_student(uuid, text, text, date, text, double precision, double precision) to service_role;
grant execute on function public.archive_student(uuid) to service_role;
grant execute on function public.student_duplicate_exists(text, date, uuid) to service_role;
grant execute on function public.link_student_by_nfc(text) to service_role;
grant execute on function public.add_destination(uuid, text, text, double precision, double precision) to service_role;
grant execute on function public.update_destination(uuid, text, text, double precision, double precision) to service_role;
grant execute on function public.delete_destination(uuid) to service_role;

drop policy if exists "students for linked parents" on public.students;
create policy "students for linked parents"
    on public.students
    for select
    to authenticated
    using (private.is_parent_of(id));

drop policy if exists "own links" on public.student_parents;
create policy "own links"
    on public.student_parents
    for select
    to authenticated
    using (parent_id = auth.uid());

drop policy if exists "destinations for linked parents" on public.destinations;
create policy "destinations for linked parents"
    on public.destinations
    for select
    to authenticated
    using (private.is_parent_of(student_id));

grant usage on schema public to authenticated;
grant usage on schema public to service_role;
grant select on table public.students to authenticated;
grant select on table public.student_parents to authenticated;
grant select on table public.destinations to authenticated;
grant select on table public.students to service_role;
grant select on table public.student_parents to service_role;
grant select on table public.destinations to service_role;
