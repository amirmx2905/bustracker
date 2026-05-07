-- Run after schema.sql.
--
-- Kept separate from schema.sql because creating an auth.users trigger in the same
-- transaction as public table/policy DDL can deadlock under live signup traffic.

create schema if not exists private;
revoke all on schema private from public;

create or replace function private.sync_profile_from_auth_metadata(
    target_user_id uuid,
    metadata jsonb,
    require_complete boolean default true
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    role_text text := nullif(btrim(coalesce(metadata ->> 'role', '')), '');
    full_name_text text := nullif(btrim(coalesce(metadata ->> 'full_name', '')), '');
begin
    if require_complete and (role_text is null or full_name_text is null) then
        raise exception 'Missing required profile metadata for auth user %', target_user_id
            using errcode = 'P0001';
    end if;

    if role_text is null or full_name_text is null then
        return;
    end if;

    if role_text not in ('parent', 'driver') then
        raise exception 'Invalid role metadata for auth user %: %', target_user_id, role_text
            using errcode = 'P0001';
    end if;

    insert into public.profiles (id, role, full_name)
    values (target_user_id, role_text::public.user_role, full_name_text)
    on conflict (id) do update
    set
        role = excluded.role,
        full_name = excluded.full_name;
end;
$$;

revoke all on function private.sync_profile_from_auth_metadata(uuid, jsonb, boolean) from public;

create or replace function private.handle_auth_user_created()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    perform private.sync_profile_from_auth_metadata(new.id, new.raw_user_meta_data, true);
    return new;
end;
$$;

revoke all on function private.handle_auth_user_created() from public;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function private.handle_auth_user_created();
