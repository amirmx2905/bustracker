-- Run this after supabase/sql/phase2_schema.sql.
-- It is intentionally separate from the main schema file so auth.users trigger DDL does
-- not share a transaction with public.profiles and related policy DDL, which can deadlock
-- under live signup traffic.

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
    pickup_label_text text := nullif(btrim(coalesce(metadata ->> 'pickup_label', '')), '');
    pickup_address_text text := nullif(btrim(coalesce(metadata ->> 'pickup_address', '')), '');
    pickup_point_text text := nullif(btrim(coalesce(metadata ->> 'pickup_point', '')), '');
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

    if role_text = 'parent' then
        if pickup_address_text is null or pickup_point_text is null then
            raise exception 'Parent profile metadata is incomplete for auth user %', target_user_id
                using errcode = 'P0001';
        end if;

        if pickup_label_text is null then
            pickup_label_text := 'Home';
        end if;
    else
        pickup_label_text := null;
        pickup_address_text := null;
        pickup_point_text := null;
    end if;

    insert into public.profiles (
        id,
        role,
        full_name,
        pickup_label,
        pickup_point,
        pickup_address
    )
    values (
        target_user_id,
        role_text::public.user_role,
        full_name_text,
        pickup_label_text,
        case
            when pickup_point_text is null then null
            else ST_GeogFromText(pickup_point_text)
        end,
        pickup_address_text
    )
    on conflict (id) do update
    set
        role = excluded.role,
        full_name = excluded.full_name,
        pickup_label = excluded.pickup_label,
        pickup_point = excluded.pickup_point,
        pickup_address = excluded.pickup_address;
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

-- Existing users created before this trigger was installed can use the in-app repair flow.
-- If you later need a bulk backfill, run it in a dedicated quiet-period SQL script rather
-- than mixing it into the main schema deployment.
