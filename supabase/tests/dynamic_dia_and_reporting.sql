-- Transactional fixtures for the canonical DIA, status revisions and reporting RPCs.
begin;

insert into auth.users(id,email,raw_app_meta_data) values
  ('a0080000-0000-4000-8000-000000000001','test-008-admin@example.invalid',
   '{"ukm_staff_provisioning":{"role":"admin","full_name":"Report Test Admin"}}'),
  ('a0080000-0000-4000-8000-000000000002','test-008-manager@example.invalid',
   '{"ukm_staff_provisioning":{"role":"manager","full_name":"Report Test Manager"}}');

insert into public.machines(id,name,number,dia) values
  (31001,'UKM 008 A','UKM-008-A','30A-008'), (31002,'UKM 008 B','UKM-008-B','30A-008'),
  (31003,'UKM 008 C','UKM-008-C','854008');

set local role authenticated;
select set_config('request.jwt.claim.sub','a0080000-0000-4000-8000-000000000002',true);
do $$
declare
  d date := (now() at time zone 'Asia/Kolkata')::date-5;
  a1 uuid; a2 uuid; b uuid; party_a uuid;
  p1 uuid; p2 uuid; p3 uuid; p4 uuid; p5 uuid;
  result jsonb; line jsonb; edit_version timestamptz; edit_lines jsonb;
  criteria record; actual numeric;
  shape jsonb := '{"loop_length":"2.55","ordered_kg":"100.125","specification":"008 Jersey"}';
begin
  a1 := public.ukm_save_job(null,null,d,'UKM-008-1','UKM 008 Party A','Yarn',
    jsonb_build_array(
      shape || '{"dia":"30A-008"}',
      shape || '{"dia":"30A-008","loop_length":"3.1","ordered_kg":"40","specification":"008 Rib"}',
      shape || '{"dia":"854008","ordered_kg":"25"}'));
  a2 := public.ukm_save_job(null,null,d,'UKM-008-2','UKM 008 Party A','Yarn',
    jsonb_build_array(shape || '{"dia":"30A-008","ordered_kg":"50"}'));
  b := public.ukm_save_job(null,null,d,'UKM-008-3','UKM 008 Party B','Yarn',
    jsonb_build_array(shape || '{"dia":"854008","ordered_kg":"20"}'));
  select party_id into strict party_a from public.jobs where id=a1;
  select id into strict p1 from public.job_programs where job_id=a1 and position=1;
  select id into strict p2 from public.job_programs where job_id=a1 and position=2;
  select id into strict p3 from public.job_programs where job_id=a1 and position=3;
  select id into strict p4 from public.job_programs where job_id=a2;
  select id into strict p5 from public.job_programs where job_id=b;

  for criteria in select * from (values
    (a1,d-1,'morning',p1,20.125),(a1,d,'morning',p1,10.111),
    (a1,d,'night',p1,5.222),(a1,d,'night',p2,3.333),(a1,d,'morning',p3,4.444),
    (a1,d+1,'morning',p1,12.345),(a1,d+2,'morning',p1,40.555),
    (a2,d+1,'night',p4,8.888),(b,d+1,'morning',p5,2.222)
  ) fixture(job_id,day,shift,program_id,kg) loop
    perform public.ukm_save_production(criteria.job_id,criteria.day,criteria.shift::public.ukm_shift,
      jsonb_build_array(jsonb_build_object('program_id',criteria.program_id,'quantity_kg',criteria.kg)));
  end loop;

  if (select count(*) from jsonb_array_elements(public.ukm_production_sheet(a1,d,'morning')->'programs')) <> 3 then
    raise exception 'Production sheet did not include exactly the three individual programs.';
  end if;

  for criteria in select * from (values
    (null::uuid,null::uuid,null::text,46.565),(a1,null,null,35.455),
    (null,party_a,null,44.343),(null,null,'30A-008',39.899),
    (a1,null,'30A-008',31.011),(null,party_a,'30A-008',39.899)
  ) filters(job_id,party_id,dia,expected) loop
    result := public.ukm_report(d,d+1,null,criteria.job_id,criteria.party_id,criteria.dia);
    select sum((item->>'quantity_kg')::numeric) into actual
      from jsonb_array_elements(result->'entries') item
      where item->>'job_number' like 'UKM-008-%';
    if actual is distinct from criteria.expected then
      raise exception 'Filtered period total is %, expected %.',actual,criteria.expected;
    end if;
  end loop;

  result := public.ukm_report(d,d+1,null,a1,null,null);
  select item into strict line from jsonb_array_elements(result->'days') item
    where item->>'program_id'=p1::text and item->>'production_date'=d::text;
  if (line->>'morning_kg',line->>'night_kg',line->>'daily_kg',line->>'cumulative_kg',line->>'balance_kg')
      is distinct from ('10.111','5.222','15.333','35.458','64.667') then
    raise exception 'Incorrect first-day production or historical balance: %.',line;
  end if;
  select item into strict line from jsonb_array_elements(result->'days') item
    where item->>'program_id'=p1::text and item->>'production_date'=(d+1)::text;
  if (line->>'cumulative_kg',line->>'balance_kg') is distinct from ('47.803','52.322') then
    raise exception 'Second-day balance includes outside production.';
  end if;
  if (select sum((item->>'balance_kg')::numeric) from jsonb_array_elements(result->'programs') item)
      is distinct from 109.545
    or (select sum((item->>'ordered_kg')::numeric) from jsonb_array_elements(result->'programs') item)
      is distinct from 165.125
    or (select sum((item->>'daily_kg')::numeric) from jsonb_array_elements(result->'days') item
      where item->>'production_date'=d::text) is distinct from 23.110
    or (select count(*) from jsonb_array_elements(result->'days') item where item->>'dia'='30A-008'
      and item->>'production_date'=d::text) <> 2 then
    raise exception 'Programs, daily subtotals, order or pending quantities were merged or counted twice.';
  end if;
  if jsonb_array_length(public.ukm_report(d-10,d-9,null,a1,null,null)->'entries') <> 0 then
    raise exception 'Empty date range returned production.';
  end if;
  result := public.ukm_report(d,d,'night',a1,null,'30A-008');
  if jsonb_array_length(result->'entries') <> 2
    or (select sum((item->>'daily_kg')::numeric) from jsonb_array_elements(result->'days') item) <> 8.555 then
    raise exception 'Shift report contains production from the wrong shift.';
  end if;

  result := public.ukm_write_running(31001::smallint,d,true);
  if result->>'revision' <> '1' then raise exception 'First revision was not 1.'; end if;
  result := public.ukm_write_running(31001::smallint,d,true);
  if result->>'revision' <> '1' then raise exception 'Duplicate write changed revision.'; end if;
  result := public.ukm_write_running(31001::smallint,d,false);
  if result->>'revision' <> '2' or not exists(select from jsonb_array_elements(public.ukm_machine_day(d)) m
      where m->>'id'='31001' and m->>'running'='false' and m->>'status_revision'='2') then
    raise exception 'Machine status revisions or idempotence failed.';
  end if;
  perform public.ukm_set_booking(31001::smallint,d,true);

  perform set_config('request.jwt.claim.sub','a0080000-0000-4000-8000-000000000001',true);
  if (select sum((item->>'daily_kg')::numeric) from jsonb_array_elements(
    public.ukm_report(d,d+1,null,a1,null,'30A-008')->'days') item) is distinct from 31.011 then
    raise exception 'Admin does not get the same report as Manager.';
  end if;
  begin
    perform public.ukm_write_running(31001::smallint,d,true);
    raise exception 'Admin changed Manager status.';
  exception when insufficient_privilege then null;
  end;
  perform public.ukm_save_machine_label(31002::smallint,'UKM-008-B','A/008-RIB','','');
  if not exists(select from public.machines where id=31001 and dia='30A-008' and removed_at is null) then
    raise exception 'Editing a duplicate DIA removed the active identifier prematurely.';
  end if;
  if public.ukm_remove_machine(31001::smallint) or not public.ukm_remove_machine(31002::smallint) then
    raise exception 'Machine removal lost history or failed to delete an unused machine.';
  end if;
  if not (public.ukm_report_dias(d,d+1) ? '30A-008')
    or not (public.ukm_report_dias(d,d+1) ? '854008')
    or not exists(select from public.schedules where machine_id=31001 and dia='30A-008') then
    raise exception 'Historical DIA or booking was lost after removing a machine.';
  end if;

  perform set_config('request.jwt.claim.sub','a0080000-0000-4000-8000-000000000002',true);
  select j.updated_at into strict edit_version from public.jobs j where id=a1;
  select jsonb_agg(to_jsonb(p) order by position) into edit_lines
    from public.ukm_program_totals p where job_id=a1;
  perform public.ukm_save_job(a1,edit_version,d,'UKM-008-1','UKM 008 Party A','New yarn',edit_lines);
  if (select dia from public.job_programs where id=p1) <> '30A-008' then
    raise exception 'An existing job lost its historical DIA.';
  end if;
  begin
    perform public.ukm_save_job(null,null,d,'UKM-008-NEW','UKM 008 Party A','Yarn',
      jsonb_build_array(shape || '{"dia":"30A-008"}'));
    raise exception 'A new job accepted an archived DIA.' using errcode='XX000';
  exception when raise_exception then
    if sqlerrm not like '%active machine%' then raise; end if;
  end;
end;
$$;
rollback;
