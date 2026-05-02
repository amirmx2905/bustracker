-- Update these emails so they match the parent accounts you created in the app.
-- Run supabase/sql/phase2_schema.sql first, then supabase/sql/phase2_auth_profile_sync.sql.
-- Existing accounts created before the trigger was installed must be repaired in-app first.

do $$
declare
    parent_one_id uuid;
    parent_two_id uuid;
begin
    select p.id
    into parent_one_id
    from public.profiles p
    join auth.users u on u.id = p.id
    where u.email = 'amir.flores.cardona@gmail.com';

    select p.id
    into parent_two_id
    from public.profiles p
    join auth.users u on u.id = p.id
    where u.email = 'test2@test.com';

    if parent_one_id is null or parent_two_id is null then
        raise exception 'Run phase2_schema.sql and phase2_auth_profile_sync.sql, then create or repair the parent accounts before updating the emails at the top of supabase/sql/phase2_seed_demo.sql.';
    end if;

    insert into public.students (
        id,
        nfc_uid,
        full_name,
        date_of_birth,
        pickup_point,
        pickup_address,
        active
    )
    values
        (
            '11111111-1111-1111-1111-111111111111',
            'NFC-DEMO-001',
            'Sofia Ramirez',
            date '2016-04-12',
            ST_GeogFromText('SRID=4326;POINT(-99.1332 19.4326)'),
            '123 Maple Ave, Demo City',
            true
        ),
        (
            '22222222-2222-2222-2222-222222222222',
            'NFC-DEMO-002',
            'Mateo Ortega',
            date '2015-09-03',
            ST_GeogFromText('SRID=4326;POINT(-99.1410 19.4271)'),
            '456 Cedar St, Demo City',
            true
        )
    on conflict (id) do update
    set
        nfc_uid = excluded.nfc_uid,
        full_name = excluded.full_name,
        date_of_birth = excluded.date_of_birth,
        pickup_point = excluded.pickup_point,
        pickup_address = excluded.pickup_address,
        active = excluded.active;

    insert into public.student_parents (student_id, parent_id, is_registrar)
    values
        ('11111111-1111-1111-1111-111111111111', parent_one_id, true),
        ('22222222-2222-2222-2222-222222222222', parent_two_id, true)
    on conflict (student_id, parent_id) do update
    set
        is_registrar = excluded.is_registrar,
        linked_at = now();

    insert into public.destinations (id, student_id, label, point, address)
    values
        (
            '33333333-3333-3333-3333-333333333333',
            '11111111-1111-1111-1111-111111111111',
            'School',
            ST_GeogFromText('SRID=4326;POINT(-99.1295 19.4363)'),
            'North Campus, Demo City'
        ),
        (
            '44444444-4444-4444-4444-444444444444',
            '22222222-2222-2222-2222-222222222222',
            'School',
            ST_GeogFromText('SRID=4326;POINT(-99.1455 19.4302)'),
            'South Campus, Demo City'
        )
    on conflict (id) do update
    set
        student_id = excluded.student_id,
        label = excluded.label,
        point = excluded.point,
        address = excluded.address;
end
$$;
