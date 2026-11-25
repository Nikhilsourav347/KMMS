begin;
create function public.ukm_require_manager() returns void language plpgsql stable security definer set search_path='' as $$
begin
  if public.ukm_role_for_user() is distinct from 'manager'::public.ukm_role then
    raise exception 'Manager access is required.' using errcode='42501';
  end if;
end
$$;

create function public.ukm_shift_at(p_time timestamptz) returns table(shift_date date, shift public.ukm_shift)
language sql immutable set search_path='' as $$
  select (local_time - interval '8 hours 30 minutes')::date,
    case when local_time::time >= '08:30' and local_time::time < '20:30'
         then 'morning'::public.ukm_shift else 'night'::public.ukm_shift end
  from (select p_time at time zone 'Asia/Kolkata' as local_time) t
$$;

create function public.ukm_reset_shift(p_time timestamptz default clock_timestamp()) returns void
language plpgsql security definer set search_path='' as $$
declare target record; prior record; next_date date; next_shift public.ukm_shift;
begin
  perform pg_advisory_xact_lock(35680830);
  select * into target from public.ukm_shift_at(p_time);
  for prior in select * from public.machine_status
    where (shift_date,shift) < (target.shift_date,target.shift) order by machine_id
  loop
    insert into public.machine_status_history
    select prior.machine_id,prior.shift_date,prior.shift,prior.status,m.dia,
      j.job_number,p.name,prior.updated_at,prior.updated_by
    from public.machines m
    left join public.jobs j on j.id=prior.job_id
    left join public.parties p on p.id=j.party_id
    where m.id=prior.machine_id on conflict do nothing;
    next_date := prior.shift_date + case when prior.shift='night' then 1 else 0 end;
    next_shift := case when prior.shift='night' then 'morning' else 'night' end;
    while (next_date,next_shift) < (target.shift_date,target.shift) loop
      insert into public.machine_status_history(machine_id,shift_date,shift,status,dia,updated_at)
      select prior.machine_id,next_date,next_shift,'unconfirmed',m.dia,
        (next_date + case when next_shift='morning' then time '08:30' else time '20:30' end) at time zone 'Asia/Kolkata'
      from public.machines m where m.id=prior.machine_id on conflict do nothing;
      if next_shift='night' then next_date := next_date + 1; next_shift := 'morning';
      else next_shift := 'night'; end if;
    end loop;
  end loop;
  insert into public.machine_status(machine_id,shift_date,shift,updated_at)
  select id,target.shift_date,target.shift,
    (target.shift_date + case when target.shift='morning' then time '08:30' else time '20:30' end) at time zone 'Asia/Kolkata'
  from public.machines
  on conflict(machine_id) do update
    set shift_date=excluded.shift_date,shift=excluded.shift,status='unconfirmed',job_id=null,
      updated_at=excluded.updated_at,updated_by=null
    where (public.machine_status.shift_date,public.machine_status.shift) < (excluded.shift_date,excluded.shift);
end
$$;

create function public.ukm_machine_update(p_machine smallint,p_date date,p_shift public.ukm_shift,p_status public.ukm_status,p_job uuid)
returns void language plpgsql security definer set search_path='' as $$
declare current_window record;
begin
  perform public.ukm_require_manager();
  perform pg_advisory_xact_lock(35680830);
  select * into current_window from public.ukm_shift_at(clock_timestamp());
  if (p_date,p_shift) is distinct from (current_window.shift_date,current_window.shift) then
    raise exception 'The shift has changed. Refresh the screen and confirm the new shift.';
  end if;
  perform public.ukm_reset_shift();
  update public.machine_status set status=p_status,job_id=p_job,updated_at=clock_timestamp(),updated_by=auth.uid()
  where machine_id=p_machine and shift_date=p_date and shift=p_shift;
  if not found then raise exception 'Machine or current shift is unavailable.'; end if;
end
$$;

create function public.ukm_machine_dia(p_machine smallint,p_dia public.ukm_dia) returns void
language plpgsql security definer set search_path='' as $$
begin
  perform public.ukm_require_manager();
  perform pg_advisory_xact_lock(35682600);
  perform public.ukm_reset_shift();
  if exists (
    select from public.schedules where machine_id=p_machine and dia is distinct from p_dia
      and end_date >= (clock_timestamp() at time zone 'Asia/Kolkata')::date
  ) then raise exception 'Move or remove active and future bookings before changing this DIA.'; end if;
  update public.machines set dia=p_dia,updated_at=clock_timestamp() where id=p_machine;
  if not found then raise exception 'Machine does not exist.'; end if;
end
$$;

create function public.ukm_save_schedule(p_id uuid,p_version timestamptz,p_dia public.ukm_dia,
  p_start date,p_end date,p_machine smallint,p_job uuid,p_party text,p_remarks text,p_delete boolean default false)
returns uuid language plpgsql security definer set search_path='' as $$
declare saved uuid; party uuid; existing public.schedules%rowtype;
begin
  perform public.ukm_require_manager();
  perform pg_advisory_xact_lock(35682600);
  if p_id is not null then
    select * into existing from public.schedules where id=p_id for update;
    if not found or existing.updated_at is distinct from p_version then
      raise exception 'This booking changed. Reload before editing it.';
    end if;
  end if;
  if p_delete then
    if p_id is null then raise exception 'Select a booking to remove.'; end if;
    delete from public.schedules where id=p_id;
    return p_id;
  end if;
  if p_machine is not null and not exists(select from public.machines where id=p_machine and dia=p_dia)
     and (p_id is null or (p_machine,p_dia,p_start,p_end) is distinct from (existing.machine_id,existing.dia,existing.start_date,existing.end_date)) then
    raise exception 'Choose a machine assigned to the selected DIA.';
  end if;
  if p_job is not null then
    select j.party_id into strict party from public.jobs j where j.id=p_job;
  elsif nullif(trim(p_party),'') is not null then
    insert into public.parties(name) values(trim(p_party))
      on conflict(normalized) do update set name=public.parties.name returning id into party;
  end if;
  if p_id is null then
    insert into public.schedules(dia,start_date,end_date,machine_id,job_id,party_id,remarks)
    values(p_dia,p_start,p_end,p_machine,p_job,party,coalesce(trim(p_remarks),'')) returning id into saved;
  else
    update public.schedules set dia=p_dia,start_date=p_start,end_date=p_end,machine_id=p_machine,
      job_id=p_job,party_id=party,remarks=coalesce(trim(p_remarks),''),updated_at=clock_timestamp(),updated_by=auth.uid()
      where id=p_id returning id into saved;
  end if;
  return saved;
exception when exclusion_violation then
  raise exception 'This machine already has a booking during the selected dates.';
end
$$;

create function public.ukm_save_job(p_id uuid,p_version timestamptz,p_date date,p_number text,p_party text,p_yarn text,p_programs jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare job uuid; party uuid; spec uuid; current_program uuid; line jsonb; seen uuid[] := '{}';
  program_position integer := 0; ordered numeric; loop_size numeric; protected boolean; produced numeric; existing record;
begin
  perform public.ukm_require_manager();
  if jsonb_typeof(p_programs) is distinct from 'array' or jsonb_array_length(p_programs)=0 then
    raise exception 'Add at least one complete program.';
  end if;
  if p_id is not null then
    perform 1 from public.jobs where id=p_id and updated_at=p_version for update;
    if not found then raise exception 'This job changed. Reload it before saving.'; end if;
  end if;
  insert into public.parties(name) values(trim(p_party))
    on conflict(normalized) do update set name=public.parties.name returning id into party;
  if p_id is null then
    insert into public.jobs(job_number,job_date,party_id,yarn)
    values(trim(p_number),p_date,party,trim(p_yarn)) returning id into job;
  else
    update public.jobs set job_number=trim(p_number),job_date=p_date,party_id=party,yarn=trim(p_yarn),
      updated_at=clock_timestamp(),updated_by=auth.uid() where id=p_id returning id into job;
  end if;
  for line in select value from jsonb_array_elements(p_programs) loop
    program_position := program_position+1;
    ordered := (line->>'ordered_kg')::numeric;
    loop_size := (line->>'loop_length')::numeric;
    if ordered is null or loop_size is null or ordered <> round(ordered,3) or loop_size <> round(loop_size,3) then
      raise exception 'Enter program quantities and loop lengths with up to three decimal places.';
    end if;
    insert into public.specifications(name) values(trim(line->>'specification'))
      on conflict(normalized) do update set name=public.specifications.name returning id into spec;
    current_program := nullif(line->>'id','')::uuid;
    if current_program is null then
      insert into public.job_programs(job_id,dia,loop_length,ordered_kg,specification_id,remarks,position)
      values(job,(line->>'dia')::public.ukm_dia,loop_size,ordered,spec,coalesce(trim(line->>'remarks'),''),program_position)
      returning id into current_program;
    else
      if current_program=any(seen) then raise exception 'A program occurs more than once.'; end if;
      select p.dia,p.loop_length,p.specification_id,p.ordered_kg into existing
        from public.job_programs p where p.id=current_program and p.job_id=job for update;
      if not found then raise exception 'A program does not belong to this job.'; end if;
      select count(*)>0,coalesce(sum(quantity_kg),0) into protected,produced
        from public.production_entries where program_id=current_program;
      if protected and (existing.dia,existing.loop_length,existing.specification_id)
          is distinct from ((line->>'dia')::public.ukm_dia,loop_size,spec) then
        raise exception 'DIA, loop length and specification are locked once production is recorded.';
      end if;
      if protected and ordered < produced and ordered <> existing.ordered_kg
          and not (select allow_overproduction from public.mill_settings) then
        raise exception 'Ordered quantity cannot be lower than recorded production.';
      end if;
      update public.job_programs set dia=(line->>'dia')::public.ukm_dia,loop_length=loop_size,ordered_kg=ordered,
        specification_id=spec,remarks=coalesce(trim(line->>'remarks'),''),position=program_position,
        updated_at=clock_timestamp() where id=current_program;
    end if;
    seen := array_append(seen,current_program);
  end loop;
  if exists(select from public.job_programs p join public.production_entries e on e.program_id=p.id
    where p.job_id=job and not(p.id=any(seen))) then
    raise exception 'A program with production history cannot be removed.';
  end if;
  delete from public.job_programs where job_id=job and not(id=any(seen));
  return job;
exception when unique_violation then
  raise exception 'This job number is already in use.';
end
$$;

create function public.ukm_save_production(p_job uuid,p_date date,p_shift public.ukm_shift,p_lines jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare line jsonb; program uuid; ordered numeric; other numeric; quantity numeric;
  current_entry public.production_entries%rowtype; expected timestamptz; seen uuid[] := '{}'; allow_extra boolean;
begin
  perform public.ukm_require_manager();
  if p_date is null or p_shift is null or jsonb_typeof(p_lines) is distinct from 'array' or jsonb_array_length(p_lines)=0 then
    raise exception 'Select a date and shift and enter at least one quantity.';
  end if;
  if p_date > (clock_timestamp() at time zone 'Asia/Kolkata')::date then raise exception 'Production dates cannot be in the future.'; end if;
  perform 1 from public.jobs where id=p_job for update;
  if not found then raise exception 'The selected job no longer exists.'; end if;
  select allow_overproduction into strict allow_extra from public.mill_settings;
  for line in select value from jsonb_array_elements(p_lines) loop
    program := (line->>'program_id')::uuid;
    quantity := (line->>'quantity_kg')::numeric;
    expected := (line->>'version')::timestamptz;
    if quantity is null or quantity < 0 or quantity <> round(quantity,3) then
      raise exception 'Enter a non-negative quantity with up to three decimal places.';
    end if;
    if program=any(seen) then raise exception 'A program occurs more than once.'; end if;
    seen := array_append(seen,program);
    select ordered_kg into ordered from public.job_programs where id=program and job_id=p_job for update;
    if not found then raise exception 'A program does not belong to this job.'; end if;
    select * into current_entry from public.production_entries
      where program_id=program and production_date=p_date and shift=p_shift for update;
    if current_entry.updated_at is distinct from expected then
      raise exception 'Production changed in another session. Reload before saving.';
    end if;
    select coalesce(sum(quantity_kg),0) into other from public.production_entries
      where program_id=program and (production_date,shift) <> (p_date,p_shift);
    if quantity + other > ordered and not allow_extra then
      raise exception 'Production exceeds the remaining ordered quantity for a program.';
    end if;
    if current_entry.id is null then
      insert into public.production_entries(program_id,production_date,shift,quantity_kg)
      values(program,p_date,p_shift,quantity);
    else
      update public.production_entries set quantity_kg=quantity,updated_at=clock_timestamp(),updated_by=auth.uid()
      where id=current_entry.id and quantity_kg is distinct from quantity;
    end if;
  end loop;
end
$$;

revoke all on function public.ukm_require_manager(), public.ukm_shift_at(timestamptz), public.ukm_reset_shift(timestamptz),
  public.ukm_machine_update(smallint,date,public.ukm_shift,public.ukm_status,uuid), public.ukm_machine_dia(smallint,public.ukm_dia),
  public.ukm_save_schedule(uuid,timestamptz,public.ukm_dia,date,date,smallint,uuid,text,text,boolean),
  public.ukm_save_job(uuid,timestamptz,date,text,text,text,jsonb),
  public.ukm_save_production(uuid,date,public.ukm_shift,jsonb) from public,anon,authenticated;
grant execute on function public.ukm_machine_update(smallint,date,public.ukm_shift,public.ukm_status,uuid),
  public.ukm_machine_dia(smallint,public.ukm_dia),
  public.ukm_save_schedule(uuid,timestamptz,public.ukm_dia,date,date,smallint,uuid,text,text,boolean),
  public.ukm_save_job(uuid,timestamptz,date,text,text,text,jsonb),
  public.ukm_save_production(uuid,date,public.ukm_shift,jsonb) to authenticated;
commit;
