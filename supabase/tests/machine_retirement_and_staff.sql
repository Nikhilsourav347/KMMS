-- Disposable integration fixtures. Run after applying all migrations.
begin;

insert into auth.users (id, email, raw_app_meta_data)
values
  ('a0060000-0000-4000-8000-000000000001', 'test-006-admin@example.invalid',
   '{"ukm_staff_provisioning":{"role":"admin","full_name":"Test Admin","phone":"12345"}}'),
  ('a0060000-0000-4000-8000-000000000002', 'test-006-manager@example.invalid',
   '{"ukm_staff_provisioning":{"role":"manager","full_name":"Test Manager"}}');

do $$
begin
  if not exists (select from public.profiles
    where id = 'a0060000-0000-4000-8000-000000000001'
      and role = 'admin' and full_name = 'Test Admin' and phone = '12345') then
    raise exception 'Admin profile failed to provision.';
  end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a0060000-0000-4000-8000-000000000001', true);
select public.ukm_save_machine(null, 'test-006-unused', '24', '', '');
select public.ukm_save_machine(null, 'test-006-used', '24', '', '');
select set_config('request.jwt.claim.sub', 'a0060000-0000-4000-8000-000000000002', true);

do $$
declare used_id smallint;
begin
  select id into strict used_id from public.machines where number = 'test-006-used';
  begin
    perform public.ukm_remove_machine(used_id);
    raise exception 'Manager could remove a machine.';
  exception when insufficient_privilege then null;
  end;
  perform public.ukm_set_running(used_id, current_date, true);
end;
$$;

select set_config('request.jwt.claim.sub', 'a0060000-0000-4000-8000-000000000001', true);
do $$
declare unused_id smallint; used_id smallint;
begin
  select id into strict unused_id from public.machines where number = 'test-006-unused';
  select id into strict used_id from public.machines where number = 'test-006-used';
  perform public.ukm_save_machine(unused_id, 'test-006-unused', '26', '', '');
  if (select dia from public.machines where id = unused_id) <> '26' then
    raise exception 'Machine edit failed.';
  end if;
  if not public.ukm_remove_machine(unused_id) then raise exception 'Unused machine was archived.'; end if;
  if public.ukm_remove_machine(used_id) then raise exception 'Used machine was deleted.'; end if;
  if exists (select from public.machines where id = unused_id or (id = used_id and removed_at is null))
     or not exists (select from public.daily_machine_status where machine_id = used_id and running) then
    raise exception 'Machine removal failed to preserve or hide a record.';
  end if;
  if exists (
    select from jsonb_array_elements(public.ukm_machine_day(current_date)) as m
    where (m->>'id')::smallint in (used_id, unused_id)
  ) then raise exception 'A removed machine is still visible.'; end if;
end;
$$;
rollback;
