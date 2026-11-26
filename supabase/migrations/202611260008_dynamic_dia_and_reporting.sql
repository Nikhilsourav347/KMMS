begin;

-- Consolidate the previously separate machine labels into one DIA type.
-- Keep the old numeric domain until all functions that use it are replaced.
create domain public.ukm_dia_identifier as text
  check (value = trim(value) and length(value) between 1 and 40 and value !~ '[[:cntrl:]]');

drop view public.ukm_jobs;
drop view public.ukm_program_totals;
alter table public.job_programs drop constraint ukm_program_dia_catalog;
alter table public.job_programs alter column dia type public.ukm_dia_identifier using dia::text;
alter table public.machines alter column dia type public.ukm_dia_identifier
  using trim(coalesce(dia_label,dia::text));
alter table public.machines drop column dia_label;
alter table public.schedules alter column dia type public.ukm_dia_identifier using dia::text;
alter table public.machine_status_history alter column dia type public.ukm_dia_identifier using dia::text;
create index ukm_active_machine_dia on public.machines(dia) where removed_at is null;

create view public.ukm_program_totals with (security_invoker=true) as
  select p.*,s.name as specification,coalesce(t.produced,0) as produced_kg,
    p.ordered_kg-coalesce(t.produced,0) as balance_kg, coalesce(t.produced,0)>=p.ordered_kg as completed,
    t.entry_count > 0 as has_history
  from public.job_programs p join public.specifications s on s.id=p.specification_id
  left join lateral (
    select sum(quantity_kg) produced,count(*) entry_count from public.production_entries e where e.program_id=p.id
  ) t on true;
create view public.ukm_jobs with (security_invoker=true) as
  select j.*,p.name as party,coalesce(t.ordered,0) as ordered_kg,coalesce(t.produced,0) as produced_kg,
    coalesce(t.done,false) as completed
  from public.jobs j join public.parties p on p.id=j.party_id
  left join lateral(select sum(ordered_kg) ordered,sum(produced_kg) produced,bool_and(completed) done
    from public.ukm_program_totals t where job_id=j.id) t on true;
revoke all on public.ukm_program_totals,public.ukm_jobs from anon,authenticated;
grant select on public.ukm_program_totals,public.ukm_jobs to authenticated;

create or replace function public.ukm_save_machine_label(
  p_id smallint,p_number text,p_dia_label text,p_type text,p_specifications text
) returns void language plpgsql security definer set search_path='' as $$
declare label text := trim(p_number); machine_name text; machine_type text := trim(coalesce(p_type,''));
  details text := trim(coalesce(p_specifications,'')); next_id smallint; diameter text := trim(p_dia_label);
begin
  perform public.ukm_require_admin();
  if label is null or length(label) not between 1 and 40 then
    raise exception 'Enter a machine number.';
  end if;
  if diameter is null or length(diameter) not between 1 and 40 or diameter ~ '[[:cntrl:]]' then
    raise exception 'Enter a DIA label of up to 40 characters.';
  end if;
  if length(machine_type)>80 or length(details)>360 then raise exception 'Machine type or specifications are too long.'; end if;
  machine_name := case when label ~ '^[0-9]+$' then 'Machine ' || lpad(label,greatest(2,length(label)),'0') else label end;
  perform pg_advisory_xact_lock(91320000);
  if p_id is null then
    next_id := nextval('public.ukm_machine_id_seq'::regclass);
    insert into public.machines(id,name,number,dia,type,specifications)
    values(next_id,machine_name,label,diameter,machine_type,details);
  else
    update public.machines set name=machine_name,number=label,dia=diameter,type=machine_type,
      specifications=details,updated_at=clock_timestamp() where id=p_id and removed_at is null;
    if not found then raise exception 'Machine is unavailable.'; end if;
  end if;
exception when unique_violation then
  raise exception 'That machine number has already been registered.';
end;
$$;

create or replace function public.ukm_save_job(p_id uuid,p_version timestamptz,p_date date,p_number text,p_party text,p_yarn text,p_programs jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare job uuid; party uuid; spec uuid; current_program uuid; line jsonb; seen uuid[] := '{}';
  program_position integer := 0; ordered numeric; loop_size numeric; protected boolean; produced numeric; existing record;
  diameter public.ukm_dia_identifier; previous_dia public.ukm_dia_identifier;
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
    if nullif(trim(line->>'dia'),'') is null then raise exception 'Select a DIA.'; end if;
    diameter := trim(line->>'dia');
    current_program := nullif(line->>'id','')::uuid;
    if current_program is not null then
      if current_program=any(seen) then raise exception 'A program occurs more than once.'; end if;
      select p.dia,p.loop_length,p.specification_id,p.ordered_kg into existing
        from public.job_programs p where p.id=current_program and p.job_id=job for update;
      if not found then raise exception 'A program does not belong to this job.'; end if;
      previous_dia := existing.dia;
    else
      previous_dia := null;
    end if;
    if diameter is distinct from previous_dia then
      -- Keep the catalog check valid until the job is saved.
      perform 1 from public.machines where removed_at is null and dia=diameter limit 1 for share;
      if not found then raise exception 'Choose a DIA assigned to an active machine.'; end if;
    end if;
    if current_program is null then
      insert into public.job_programs(job_id,dia,loop_length,ordered_kg,specification_id,remarks,position)
      values(job,diameter,loop_size,ordered,spec,coalesce(trim(line->>'remarks'),''),program_position)
      returning id into current_program;
    else
      select count(*)>0,coalesce(sum(quantity_kg),0) into protected,produced
        from public.production_entries where program_id=current_program;
      if protected and (existing.dia,existing.loop_length,existing.specification_id)
          is distinct from (diameter,loop_size,spec) then
        raise exception 'DIA, loop length and specification are locked once production is recorded.';
      end if;
      if protected and ordered < produced and ordered <> existing.ordered_kg
          and not (select allow_overproduction from public.mill_settings) then
        raise exception 'Ordered quantity cannot be lower than recorded production.';
      end if;
      update public.job_programs set dia=diameter,loop_length=loop_size,ordered_kg=ordered,
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

-- The existing calendar, booking, rollover and production-sheet routines use
-- table row types or views dynamically and now read/write the canonical DIA.
drop function public.ukm_save_machine(smallint,text,public.ukm_dia,text,text);
drop function public.ukm_machine_dia(smallint,public.ukm_dia);
drop function public.ukm_save_schedule(uuid,timestamptz,public.ukm_dia,date,date,smallint,uuid,text,text,boolean);
drop function public.ukm_report(date,date,public.ukm_shift,uuid,uuid,public.ukm_dia);
drop domain public.ukm_dia;

create function public.ukm_save_machine(p_id smallint,p_number text,p_dia text,p_type text,p_specifications text)
returns void language sql security invoker set search_path='' as $$
  select public.ukm_save_machine_label(p_id,p_number,p_dia,p_type,p_specifications)
$$;

create function public.ukm_machine_dia(p_machine smallint,p_dia text) returns void
language plpgsql security definer set search_path='' as $$
begin
  perform public.ukm_require_manager();
  perform pg_advisory_xact_lock(35682600);
  perform public.ukm_reset_shift();
  if exists (
    select from public.schedules where machine_id=p_machine and dia is distinct from p_dia
      and end_date >= (clock_timestamp() at time zone 'Asia/Kolkata')::date
  ) then raise exception 'Move or remove active and future bookings before changing this DIA.'; end if;
  update public.machines set dia=p_dia,updated_at=clock_timestamp() where id=p_machine and removed_at is null;
  if not found then raise exception 'Machine does not exist.'; end if;
end
$$;

create function public.ukm_save_schedule(p_id uuid,p_version timestamptz,p_dia text,
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
  if p_machine is not null and not exists(select from public.machines where id=p_machine and removed_at is null and dia=p_dia)
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

-- Per-machine, per-day revisions order acknowledgements and Realtime events.
alter table public.daily_machine_status add column revision bigint not null default 1;

create function public.ukm_write_running(p_id smallint,p_date date,p_running boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result public.daily_machine_status%rowtype;
begin
  perform public.ukm_require_manager();
  perform 1 from public.machines where id=p_id and removed_at is null for update;
  if not found then raise exception 'Machine is unavailable.'; end if;
  insert into public.daily_machine_status as current_status(machine_id,date,running,updated_by)
    values(p_id,p_date,p_running,auth.uid())
  on conflict(machine_id,date) do update set running=excluded.running,
    updated_at=clock_timestamp(),updated_by=excluded.updated_by,revision=current_status.revision+1
  where current_status.running is distinct from excluded.running
  returning * into result;
  if not found then
    select * into strict result from public.daily_machine_status where machine_id=p_id and date=p_date;
  end if;
  return jsonb_build_object('running',result.running,'revision',result.revision);
end;
$$;

create or replace function public.ukm_set_running(p_id smallint,p_date date,p_running boolean) returns void
language plpgsql security invoker set search_path='' as $$
begin
  perform public.ukm_write_running(p_id,p_date,p_running);
end;
$$;

create or replace function public.ukm_machine_day(p_date date) returns jsonb
language sql stable security definer set search_path='' as $$
  select coalesce(jsonb_agg(to_jsonb(m) || jsonb_build_object('running',
    coalesce(d.running,(
      select s.status='running' from (
        select shift,status from public.machine_status where machine_id=m.id and shift_date=p_date
        union all
        select shift,status from public.machine_status_history where machine_id=m.id and shift_date=p_date
      ) s where s.status in ('running','stopped') order by s.shift desc limit 1
    ),false),'status_revision',coalesce(d.revision,0)) order by m.name,m.id),'[]'::jsonb)
  from public.machines m left join public.daily_machine_status d on d.machine_id=m.id and d.date=p_date
  where m.removed_at is null and public.ukm_role_for_user() is not null
$$;

create function public.ukm_report_dias(p_start date,p_end date) returns jsonb
language sql stable security invoker set search_path='' as $$
  select coalesce(jsonb_agg(dia order by dia),'[]'::jsonb)
  from (
    select distinct pr.dia from public.production_entries e
    join public.job_programs pr on pr.id=e.program_id
    where e.production_date between p_start and p_end
  ) available
$$;

create function public.ukm_report(p_start date,p_end date,p_shift public.ukm_shift,p_job uuid,p_party uuid,p_dia text)
returns jsonb language sql stable security invoker set search_path='' as $$
  with matching_programs as (
    select pr.*, j.job_number,j.job_date,j.party_id,p.name as party,j.yarn,s.name as specification
    from public.job_programs pr join public.jobs j on j.id=pr.job_id
    join public.parties p on p.id=j.party_id join public.specifications s on s.id=pr.specification_id
    where (p_job is null or j.id=p_job) and (p_party is null or j.party_id=p_party)
      and (p_dia is null or pr.dia=p_dia)
  ), entries as (
    select e.*, pr.dia,pr.position as program_position,pr.job_id,pr.job_number,
      pr.party_id,pr.party,pr.yarn,pr.loop_length,pr.specification,pr.remarks
    from public.production_entries e join matching_programs pr on pr.id=e.program_id
    where (p_start is null or e.production_date>=p_start)
      and (p_end is null or e.production_date<=p_end) and (p_shift is null or e.shift=p_shift)
  ), period_days as (
    select program_id,production_date,
      coalesce(sum(quantity_kg) filter (where shift='morning'),0) as morning_kg,
      coalesce(sum(quantity_kg) filter (where shift='night'),0) as night_kg,
      sum(quantity_kg) as daily_kg
    from entries group by program_id,production_date
  ), period as (
    select program_id,sum(daily_kg) as period_kg from period_days group by program_id
  ), included as (
    select pr.*,coalesce(period.period_kg,0) as period_kg
    from matching_programs pr left join period on period.program_id=pr.id
    where period.program_id is not null or (p_job is not null and p_start is null and p_end is null)
  ), history_days as (
    select e.program_id,e.production_date,sum(e.quantity_kg) as all_shifts_kg
    from public.production_entries e join included pr on pr.id=e.program_id
    where p_end is null or e.production_date<=p_end
    group by e.program_id,e.production_date
  ), history as (
    select program_id,production_date,sum(all_shifts_kg) over (
      partition by program_id order by production_date rows unbounded preceding
    ) as cumulative_kg
    from history_days
  ), end_totals as (
    select distinct on (program_id) program_id,cumulative_kg
    from history order by program_id,production_date desc
  ), programs as (
    select pr.*,coalesce(t.cumulative_kg,0) as produced_kg,
      pr.ordered_kg-coalesce(t.cumulative_kg,0) as balance_kg,
      case when p_end is not null then pr.ordered_kg-coalesce(t.cumulative_kg,0) end as balance_on_end_kg,
      coalesce(t.cumulative_kg,0)>=pr.ordered_kg as completed,t.program_id is not null as has_history
    from included pr left join end_totals t on t.program_id=pr.id
  ), details as (
    select d.*,pr.job_id,pr.job_number,pr.party_id,pr.party,pr.dia,pr.position as program_position,
      pr.loop_length,pr.specification,pr.ordered_kg,h.cumulative_kg,
      pr.ordered_kg-h.cumulative_kg as balance_kg
    from period_days d join included pr on pr.id=d.program_id
    join history h on h.program_id=d.program_id and h.production_date=d.production_date
  )
  select jsonb_build_object(
    'programs',coalesce((select jsonb_agg(to_jsonb(p) order by party,job_number,position,id) from programs p),'[]'),
    'entries',coalesce((select jsonb_agg(to_jsonb(e) order by production_date,shift,party,job_number,program_position,id) from entries e),'[]'),
    'days',coalesce((select jsonb_agg(to_jsonb(d) order by production_date,party,job_number,program_position,program_id) from details d),'[]'));
$$;

revoke all on function public.ukm_write_running(smallint,date,boolean),
  public.ukm_save_machine(smallint,text,text,text,text), public.ukm_machine_dia(smallint,text),
  public.ukm_save_schedule(uuid,timestamptz,text,date,date,smallint,uuid,text,text,boolean),
  public.ukm_report(date,date,public.ukm_shift,uuid,uuid,text), public.ukm_report_dias(date,date)
  from public,anon,authenticated;
grant execute on function public.ukm_write_running(smallint,date,boolean),
  public.ukm_save_machine(smallint,text,text,text,text), public.ukm_machine_dia(smallint,text),
  public.ukm_save_schedule(uuid,timestamptz,text,date,date,smallint,uuid,text,text,boolean),
  public.ukm_report(date,date,public.ukm_shift,uuid,uuid,text), public.ukm_report_dias(date,date)
  to authenticated;

notify pgrst, 'reload schema';
commit;
