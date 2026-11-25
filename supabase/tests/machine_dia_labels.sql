begin;

insert into auth.users (id, email, raw_app_meta_data) values
  ('a0070000-0000-4000-8000-000000000001', 'test-007-admin@example.invalid',
   '{"ukm_staff_provisioning":{"role":"admin","full_name":"Test Admin"}}'),
  ('a0070000-0000-4000-8000-000000000002', 'test-007-manager@example.invalid',
   '{"ukm_staff_provisioning":{"role":"manager","full_name":"Test Manager"}}');
set local role authenticated;
select set_config('request.jwt.claim.sub', 'a0070000-0000-4000-8000-000000000001', true);
select public.ukm_save_machine_label(null, 'test-007-label', '26A', '', '');
select public.ukm_save_machine_label(null, 'test-007-number', '34', '', '');

do $$
begin
  if not exists (select from public.machines where number='test-007-number' and dia=34 and dia_label is null)
     or not exists (select from public.machines where number='test-007-label' and dia is null and dia_label='26A') then
    raise exception 'Numeric or lettered DIA was stored incorrectly.';
  end if;
end;
$$;
select set_config('request.jwt.claim.sub', 'a0070000-0000-4000-8000-000000000002', true);
do $$
declare machine smallint;
begin
  select id into strict machine from public.machines where number='test-007-label';
  begin
    perform public.ukm_save_machine_label(machine, 'test-007-label', '99X', '', '');
    raise exception 'Manager edited the machine.';
  exception when insufficient_privilege then null;
  end;
  perform public.ukm_set_running(machine, current_date, true);
  perform public.ukm_set_booking(machine, current_date, true);
  if not exists (select from jsonb_array_elements(public.ukm_machine_day(current_date)) x
      where x->>'dia_label'='26A' and x->>'running'='true')
     or not exists (select from jsonb_array_elements(public.ukm_calendar(current_date, current_date)) x
      where x->>'dia_label'='26A' and (x->'booked_dates') ? current_date::text) then
    raise exception 'The label did not reach machine status or the booked schedule.';
  end if;
  perform public.ukm_set_booking(machine, current_date, false);
end;
$$;

rollback;
