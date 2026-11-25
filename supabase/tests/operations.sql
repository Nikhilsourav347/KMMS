-- Run on a disposable Supabase database after applying all migrations.
-- Fixtures and mutations are rolled back even when the final checks pass.
begin;
set local timezone='UTC';
insert into auth.users(id,email)
values ('39000000-0000-0000-0000-000000000001','ukm-test-manager@example.invalid'),
       ('39000000-0000-0000-0000-000000000002','ukm-test-admin@example.invalid'),
       ('39000000-0000-0000-0000-000000000003','ukm-test-no-role@example.invalid');
insert into public.profiles(id,full_name,role)
values ('39000000-0000-0000-0000-000000000001','Fixture Manager','manager'),
       ('39000000-0000-0000-0000-000000000002','Fixture Admin','admin');

do $$
declare result record;
begin
  select * into result from public.ukm_shift_at('2026-11-25 02:59:59Z');
  if (result.shift_date,result.shift::text) is distinct from (date '2026-11-24','night') then
    raise exception 'Before 08:30 IST must belong to the previous night shift.'; end if;
  select * into result from public.ukm_shift_at('2026-11-25 03:00:00Z');
  if (result.shift_date,result.shift::text) is distinct from (date '2026-11-25','morning') then
    raise exception 'Morning cutoff is wrong.'; end if;
  select * into result from public.ukm_shift_at('2026-11-25 15:00:00Z');
  if (result.shift_date,result.shift::text) is distinct from (date '2026-11-25','night') then
    raise exception 'Night cutoff is wrong.'; end if;
  if (select count(*) from public.machines) <> 10 then raise exception 'Expected 10 machines.'; end if;
end
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub','39000000-0000-0000-0000-000000000001',true);
do $$
declare
  job uuid;
  first_program uuid;
  second_program uuid;
  schedule uuid;
  edit_version timestamptz;
  running_status public.ukm_status;
  payload jsonb;
  shift_day date;
  current_shift public.ukm_shift;
  entry_day date := (clock_timestamp() at time zone 'Asia/Kolkata')::date - 1;
begin
  if (select public.ukm_role_for_user()) <> 'manager' then raise exception 'Manager resolution failed.'; end if;
  if (select count(*) from public.profiles) <> 1 then raise exception 'Profile RLS failed.'; end if;
  select shift_date,shift into strict shift_day,current_shift from public.machine_status where machine_id=1;
  perform public.ukm_machine_update(1::smallint,shift_day,current_shift,'running',null);
  select status into strict running_status from public.machine_status where machine_id=1;
  if running_status <> 'running' then raise exception 'Machine update failed.'; end if;

  perform public.ukm_machine_dia(1::smallint,28);
  perform public.ukm_machine_dia(2::smallint,28);
  schedule := public.ukm_save_schedule(null,null,28,entry_day,entry_day+2,1::smallint,null,
    'UKM Test Party','Three days without a job');
  perform public.ukm_save_schedule(null,null,28,entry_day+1,entry_day+1,2::smallint,null,null,'Parallel machine');
  perform public.ukm_save_schedule(null,null,34,entry_day,entry_day,null,null,null,'DIA only');
  begin
    perform public.ukm_save_schedule(null,null,28,entry_day+2,entry_day+3,1::smallint,null,null,'Conflict');
    raise exception 'Expected exclusion rule' using errcode='XX000';
  exception when raise_exception then
    if sqlerrm not like '%already has a booking%' then raise; end if;
  end;
  select updated_at into edit_version from public.schedules where id=schedule;
  perform public.ukm_save_schedule(schedule,edit_version,28,entry_day,entry_day+3,1::smallint,null,
    'UKM Test Party','Revised booking');

  payload := '[{"dia":24,"loop_length":"2.5","ordered_kg":"500.001","specification":"UKM Custom Design","remarks":"First program"},
              {"dia":24,"loop_length":"2.7","ordered_kg":"300","specification":"ukm  custom design","remarks":"Second program"}]';
  job := public.ukm_save_job(null,null,entry_day,'UKM_SQL_TEST','UKM TEST PARTY','Test yarn',payload);
  if (select count(*) from public.specifications where normalized='ukm custom design') <> 1 then
    raise exception 'Specification reuse failed.';
  end if;
  select id into strict first_program from public.job_programs where job_id=job and position=1 and remarks='First program';
  select id into strict second_program from public.job_programs where job_id=job and position=2 and remarks='Second program';
  if first_program=second_program then raise exception 'Same DIA programs lost independence.'; end if;
  begin
    perform public.ukm_save_job(null,null,entry_day,'ukm_sql_test','UKM Test Party','Test yarn',payload);
    raise exception 'Expected normalized job uniqueness' using errcode='XX000';
  exception when raise_exception then
    if sqlerrm not like '%already in use%' then raise; end if;
  end;

  payload := jsonb_build_array(jsonb_build_object('program_id',first_program,'quantity_kg','200.001'));
  perform public.ukm_save_production(job,entry_day,'morning',payload);
  begin
    perform public.ukm_save_production(job,entry_day,'morning',payload);
    raise exception 'Expected duplicate prevention' using errcode='XX000';
  exception when raise_exception then
    if sqlerrm not like '%changed in another session%' then raise; end if;
  end;

  perform public.ukm_save_production(job,entry_day,'night',
    jsonb_build_array(jsonb_build_object('program_id',first_program,'quantity_kg','100')));
  if (select balance_kg from public.ukm_program_totals where id=first_program) <> 200 then
    raise exception 'Exact balance calculation failed.'; end if;
  begin
    perform public.ukm_save_production(job,entry_day-1,'night',
      jsonb_build_array(jsonb_build_object('program_id',first_program,'quantity_kg','200.001')));
    raise exception 'Expected overproduction prevention' using errcode='XX000';
  exception when raise_exception then
    if sqlerrm not like '%exceeds%' then raise; end if;
  end;

  select updated_at into strict edit_version from public.production_entries
    where program_id=first_program and production_date=entry_day and shift='night';
  perform public.ukm_save_production(job,entry_day,'night',jsonb_build_array(
    jsonb_build_object('program_id',first_program,'quantity_kg','300','version',edit_version),
    jsonb_build_object('program_id',second_program,'quantity_kg','300')));
  if (select completed from public.ukm_jobs where id=job) is distinct from true then
    raise exception 'Job completion did not follow program totals.'; end if;

  select updated_at into edit_version from public.jobs where id=job;
  begin
    perform public.ukm_save_job(job,edit_version,entry_day,'UKM_SQL_TEST','UKM Test Party','Test yarn',
      jsonb_build_array(jsonb_build_object('id',first_program,'dia',24,'loop_length',2.5,'ordered_kg',500.001,
        'specification','UKM Custom Design','remarks','First program')));
    raise exception 'Expected production history protection' using errcode='XX000';
  exception when raise_exception then
    if sqlerrm not like '%cannot be removed%' then raise; end if;
  end;
  perform public.ukm_save_job(job,edit_version,entry_day,'UKM_SQL_TEST','UKM Test Party','Test yarn',
    jsonb_build_array(
      jsonb_build_object('id',first_program,'dia',24,'loop_length',2.5,'ordered_kg',500.001,
        'specification','UKM Custom Design','remarks','Updated first remark'),
      jsonb_build_object('id',second_program,'dia',24,'loop_length',2.7,'ordered_kg',300,
        'specification','UKM Custom Design','remarks','Second program')));
  if (select remarks from public.job_programs where id=first_program) <> 'Updated first remark' then
    raise exception 'Job edit with preserved production did not save.'; end if;

  payload := public.ukm_report(null,null,null,job,null,null);
  if jsonb_array_length(payload->'entries') <> 3 or jsonb_array_length(payload->'programs') <> 2 then
    raise exception 'Job report lost rows or counted a program twice.'; end if;
  payload := public.ukm_report(entry_day,entry_day,null,null,null,null);
  if jsonb_array_length(payload->'entries') < 3 then raise exception 'Daily report lost a shift.'; end if;
  payload := public.ukm_report(entry_day,entry_day,'night',job,null,24);
  if jsonb_array_length(payload->'entries') <> 2 then raise exception 'Date/shift report filter failed.'; end if;
  payload := public.ukm_report(entry_day-6,entry_day,null,job,null,24);
  if jsonb_array_length(payload->'entries') <> 3 or (payload->'entries'->0->>'job_id')::uuid is distinct from job then
    raise exception 'Date range report filter failed.'; end if;
  payload := public.ukm_production_sheet(job,entry_day,'night');
  if (payload->'programs'->0->>'previous_kg')::numeric <> 200.001 then
    raise exception 'Correction sheet double-counted the existing shift.'; end if;
end
$$;

select set_config('request.jwt.claim.sub','39000000-0000-0000-0000-000000000002',true);
do $$
begin
  if public.ukm_role_for_user() <> 'admin' or (select count(*) from public.machines) <> 10 then
    raise exception 'Admin read access failed.'; end if;
  begin
    perform public.ukm_machine_dia(1::smallint,30);
    raise exception 'Expected role rejection';
  exception when insufficient_privilege then null;
  end;
  begin
    delete from public.schedules;
    raise exception 'Expected direct-write rejection';
  exception when insufficient_privilege then null;
  end;
end
$$;

select set_config('request.jwt.claim.sub','39000000-0000-0000-0000-000000000003',true);
do $$
begin
  if exists(select from public.machines) or exists(select from public.ukm_jobs) then
    raise exception 'Unprovisioned account had operational read access.'; end if;
end
$$;

reset role;
do $$
declare initial record; target timestamptz; following timestamptz;
begin
  select shift_date,shift into strict initial from public.machine_status where machine_id=1;
  target := (initial.shift_date + case when initial.shift='night' then 1 else 0 end
    + case when initial.shift='night' then time '08:30' else time '20:30' end) at time zone 'Asia/Kolkata';
  following := target + interval '12 hours';
  perform public.ukm_reset_shift(target);
  perform public.ukm_reset_shift(target);
  if (select count(*) from public.machine_status_history where shift_date=initial.shift_date and shift=initial.shift) <> 10
    or (select status from public.machine_status_history where machine_id=1 and shift_date=initial.shift_date and shift=initial.shift) <> 'running'
    or (select count(*) from public.machine_status where status='unconfirmed') <> 10 then
    raise exception 'Shift snapshot, reset or idempotence failed.';
  end if;
  perform public.ukm_reset_shift(following);
  if (select count(*) from public.machine_status where status='unconfirmed') <> 10 then
    raise exception 'Second boundary failed.'; end if;
  if (select count(*) from public.production_entries e join public.job_programs p on p.id=e.program_id
    join public.jobs j on j.id=p.job_id where j.job_number='UKM_SQL_TEST') <> 3 then
    raise exception 'Rollover altered production history.'; end if;
  if not exists(select from public.audit_logs where table_name='production_entries' and operation='UPDATE'
    and before_row->>'quantity_kg' = '100.000' and after_row->>'quantity_kg' = '300.000') then
    raise exception 'Correction audit missing.'; end if;
end
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub','39000000-0000-0000-0000-000000000002',true);
do $$
begin
  perform public.ukm_save_machine(null,'20',24,'Circular','Fixture');
  if not exists(select from public.machines where number='20' and dia=24) then
    raise exception 'Admin could not register the machine.'; end if;
  begin
    perform public.ukm_set_booking(1::smallint,current_date,true);
    raise exception 'Admin could book a date.';
  exception when insufficient_privilege then null;
  end;
end
$$;

select set_config('request.jwt.claim.sub','39000000-0000-0000-0000-000000000001',true);
do $$
declare
  machine smallint;
  fixture_day date := current_date - 20;
  dates jsonb;
begin
  if public.ukm_profile()->>'email' is distinct from 'ukm-test-manager@example.invalid' then
    raise exception 'Cloud profile omitted the account email.'; end if;
  select id into strict machine from public.machines where number='20';
  perform public.ukm_set_running(machine,fixture_day,true);
  if not exists(select from jsonb_array_elements(public.ukm_machine_day(fixture_day)) as m
      where (m->>'id')::smallint=machine and (m->>'running')::boolean) then
    raise exception 'Daily machine state could not be read.'; end if;
  perform public.ukm_save_schedule(null,null,24,fixture_day,fixture_day+2,machine,null,null,'Legacy range');
  perform public.ukm_set_booking(machine,fixture_day+1,false);
  select m->'booked_dates' into strict dates
    from jsonb_array_elements(public.ukm_calendar(fixture_day,fixture_day+2)) as m where (m->>'id')::smallint=machine;
  if dates is distinct from jsonb_build_array(fixture_day,fixture_day+2) then
    raise exception 'Cancelling a date altered neighboring bookings.'; end if;
  perform public.ukm_set_booking(machine,fixture_day+1,true);
  begin
    perform public.ukm_archive_machine(machine);
    raise exception 'Manager could archive the machine.';
  exception when insufficient_privilege then null;
  end;
end
$$;

select set_config('request.jwt.claim.sub','39000000-0000-0000-0000-000000000002',true);
select public.ukm_set_manager_enabled('ukm-test-manager@example.invalid',false);
select set_config('request.jwt.claim.sub','39000000-0000-0000-0000-000000000001',true);
do $$
begin
  if public.ukm_profile() is not null or exists(select from public.jobs) then
    raise exception 'Disabled manager retained access.'; end if;
end
$$;
rollback;
