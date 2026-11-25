begin;

alter domain public.ukm_dia drop constraint ukm_dia_check;
alter domain public.ukm_dia add constraint ukm_dia_check check (value between 1 and 999);
alter table public.job_programs add constraint ukm_program_dia_catalog
  check (dia in (24,26,28,30,32,34));

alter table public.profiles add column phone text not null default '' check (length(phone) <= 40);
alter table public.profiles add column disabled_at timestamptz;
grant select, insert on public.profiles to service_role;
alter table public.machines drop constraint machines_id_check;
alter table public.machines add constraint machines_id_check check (id > 0);
alter table public.machines drop constraint machines_name_key;
alter table public.machines add column number text;
alter table public.machines add column type text not null default '';
alter table public.machines add column specifications text not null default '';
alter table public.machines add column removed_at timestamptz;
alter table public.schedules alter column dia drop not null;
create unique index ukm_active_machine_name on public.machines(lower(trim(name))) where removed_at is null;
create unique index ukm_active_machine_number on public.machines(lower(trim(number)))
  where removed_at is null and number is not null;

create or replace function public.ukm_role_for_user() returns public.ukm_role
language sql stable security definer set search_path='' as $$
  select role from public.profiles where id=auth.uid() and disabled_at is null
$$;

create function public.ukm_require_admin() returns void
language plpgsql stable security definer set search_path='' as $$
begin
  if public.ukm_role_for_user() is distinct from 'admin'::public.ukm_role then
    raise exception 'Administrator access is required.' using errcode='42501';
  end if;
end;
$$;

create table public.daily_machine_status (
  machine_id smallint not null references public.machines,
  date date not null,
  running boolean not null,
  updated_at timestamptz not null default clock_timestamp(),
  updated_by uuid references auth.users on delete set null,
  primary key (machine_id,date)
);
alter table public.daily_machine_status enable row level security;
revoke all on public.daily_machine_status from anon, authenticated;
grant select on public.daily_machine_status to authenticated;
create policy staff_read on public.daily_machine_status for select to authenticated
  using ((select public.ukm_role_for_user()) is not null);
alter publication supabase_realtime add table public.daily_machine_status;
create trigger record_audit after insert or update on public.daily_machine_status
  for each row execute function public.ukm_audit();

create function public.ukm_profile() returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('id',p.id,'full_name',p.full_name,'role',p.role,
    'email',u.email,'phone',p.phone,'mill_id','unique-knitting-mills')
  from public.profiles p join auth.users u on u.id=p.id
  where p.id=auth.uid() and p.disabled_at is null
$$;

create function public.ukm_edit_profile(p_name text,p_phone text) returns void
language plpgsql security definer set search_path='' as $$
begin
  if public.ukm_role_for_user() is null then raise exception 'Staff access is required.' using errcode='42501'; end if;
  update public.profiles set full_name=trim(p_name),phone=trim(p_phone) where id=auth.uid();
end;
$$;

create function public.ukm_managers() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  perform public.ukm_require_admin();
  return (select coalesce(jsonb_agg(jsonb_build_object(
    'id',p.id,'full_name',p.full_name,'email',u.email,'disabled',p.disabled_at is not null
  ) order by p.full_name,p.id),'[]'::jsonb)
  from public.profiles p join auth.users u on u.id=p.id where p.role='manager');
end;
$$;

create function public.ukm_set_manager_enabled(p_email text,p_enabled boolean) returns void
language plpgsql security definer set search_path='' as $$
begin
  perform public.ukm_require_admin();
  update public.profiles p set disabled_at=case when p_enabled then null else clock_timestamp() end
  from auth.users u where p.id=u.id and p.role='manager' and lower(u.email)=lower(trim(p_email));
  if not found then raise exception 'Manager account is unavailable.'; end if;
end;
$$;

create function public.ukm_save_machine(
  p_id smallint,p_number text,p_dia public.ukm_dia,p_type text,p_specifications text
) returns void language plpgsql security definer set search_path='' as $$
declare label text := trim(p_number); machine_name text; machine_type text := trim(coalesce(p_type,''));
  details text := trim(coalesce(p_specifications,'')); next_id smallint;
begin
  perform public.ukm_require_admin();
  if label is null or length(label) not between 1 and 40 or p_dia is null then
    raise exception 'Enter a machine number and a valid DIA.';
  end if;
  if length(machine_type)>80 or length(details)>360 then raise exception 'Machine type or specifications are too long.'; end if;
  machine_name := case when label ~ '^[0-9]+$' then 'Machine ' || lpad(label,greatest(2,length(label)),'0') else label end;
  perform pg_advisory_xact_lock(91320000);
  if p_id is null then
    select coalesce(max(id),0)+1 into next_id from public.machines;
    insert into public.machines(id,name,number,dia,type,specifications)
    values(next_id,machine_name,label,p_dia,machine_type,details);
  else
    update public.machines set name=machine_name,number=label,dia=p_dia,type=machine_type,
      specifications=details,updated_at=clock_timestamp() where id=p_id and removed_at is null;
    if not found then raise exception 'Machine is unavailable.'; end if;
  end if;
exception when unique_violation then
  raise exception 'That machine number has already been registered.';
end;
$$;

create function public.ukm_archive_machine(p_id smallint) returns void
language plpgsql security definer set search_path='' as $$
begin
  perform public.ukm_require_admin();
  update public.machines set removed_at=clock_timestamp(),updated_at=clock_timestamp()
  where id=p_id and removed_at is null;
  if not found then raise exception 'Machine is unavailable.'; end if;
end;
$$;

create function public.ukm_set_running(p_id smallint,p_date date,p_running boolean) returns void
language plpgsql security definer set search_path='' as $$
begin
  perform public.ukm_require_manager();
  perform 1 from public.machines where id=p_id and removed_at is null for update;
  if not found then raise exception 'Machine is unavailable.'; end if;
  insert into public.daily_machine_status(machine_id,date,running,updated_by)
  values(p_id,p_date,p_running,auth.uid())
  on conflict(machine_id,date) do update set running=excluded.running,
    updated_at=clock_timestamp(),updated_by=excluded.updated_by;
end;
$$;

create function public.ukm_machine_day(p_date date) returns jsonb
language sql stable security definer set search_path='' as $$
  select coalesce(jsonb_agg(to_jsonb(m) || jsonb_build_object('running',
    coalesce(d.running,(
      select s.status='running' from (
        select shift,status from public.machine_status where machine_id=m.id and shift_date=p_date
        union all
        select shift,status from public.machine_status_history where machine_id=m.id and shift_date=p_date
      ) s where s.status in ('running','stopped') order by s.shift desc limit 1
    ),false)) order by m.name),'[]'::jsonb)
  from public.machines m left join public.daily_machine_status d on d.machine_id=m.id and d.date=p_date
  where m.removed_at is null and public.ukm_role_for_user() is not null
$$;

create function public.ukm_calendar(p_first date,p_last date) returns jsonb
language sql stable security invoker set search_path='' as $$
  select coalesce(jsonb_agg(to_jsonb(m) || jsonb_build_object('booked_dates',coalesce((
    select jsonb_agg(day::date order by day)
    from generate_series(p_first::timestamp,p_last::timestamp,interval '1 day') day
    where exists(select 1 from public.schedules s where s.machine_id=m.id and day::date between s.start_date and s.end_date)
  ),'[]'::jsonb)) order by m.name),'[]'::jsonb)
  from public.machines m where m.removed_at is null and p_last-p_first between 0 and 62
$$;

create function public.ukm_set_booking(p_id smallint,p_date date,p_booked boolean) returns void
language plpgsql security definer set search_path='' as $$
declare machine public.machines%rowtype; booking public.schedules%rowtype;
begin
  perform public.ukm_require_manager();
  select * into machine from public.machines where id=p_id and removed_at is null for update;
  if not found then raise exception 'Machine is unavailable.'; end if;
  select * into booking from public.schedules where machine_id=p_id and p_date between start_date and end_date for update;
  if p_booked then
    if booking.id is not null then raise exception 'This machine is already scheduled on that date.'; end if;
    insert into public.schedules(dia,start_date,end_date,machine_id)
      values(machine.dia,p_date,p_date,p_id);
  else
    if booking.id is null then raise exception 'This machine is already available on that date.'; end if;
    delete from public.schedules where id=booking.id;
    if booking.start_date<p_date then
      insert into public.schedules(dia,start_date,end_date,machine_id,job_id,party_id,remarks,created_at,created_by)
      values(booking.dia,booking.start_date,p_date-1,p_id,booking.job_id,booking.party_id,booking.remarks,booking.created_at,booking.created_by);
    end if;
    if booking.end_date>p_date then
      insert into public.schedules(dia,start_date,end_date,machine_id,job_id,party_id,remarks,created_at,created_by)
      values(booking.dia,p_date+1,booking.end_date,p_id,booking.job_id,booking.party_id,booking.remarks,booking.created_at,booking.created_by);
    end if;
  end if;
exception when exclusion_violation then raise exception 'This machine is already scheduled on that date.';
end;
$$;

create or replace function public.ukm_report(p_start date,p_end date,p_shift public.ukm_shift,p_job uuid,p_party uuid,p_dia public.ukm_dia)
returns jsonb language sql stable security invoker set search_path='' as $$
  with entries as (
    select e.*, pr.dia,pr.position as program_position,j.id as job_id,j.job_number,
      p.name as party,j.yarn,pr.loop_length,s.name as specification,pr.remarks
    from public.production_entries e
    join public.job_programs pr on pr.id=e.program_id join public.jobs j on j.id=pr.job_id
    join public.parties p on p.id=j.party_id join public.specifications s on s.id=pr.specification_id
    where (p_start is null or e.production_date>=p_start) and (p_end is null or e.production_date<=p_end)
      and (p_shift is null or e.shift=p_shift) and (p_job is null or j.id=p_job)
      and (p_party is null or j.party_id=p_party) and (p_dia is null or pr.dia=p_dia)
  ), period as (select program_id,sum(quantity_kg) as period_kg from entries group by program_id),
  programs as (
    select pr.*,j.job_number,j.job_date,j.party,j.yarn,coalesce(period.period_kg,0) as period_kg,
      case when p_end is not null then pr.ordered_kg-coalesce((
        select sum(e.quantity_kg) from public.production_entries e
          where e.program_id=pr.id and e.production_date<=p_end
      ),0) end as balance_on_end_kg
    from public.ukm_program_totals pr join public.ukm_jobs j on j.id=pr.job_id
    left join period on period.program_id=pr.id
    where (period.program_id is not null or (p_job is not null and p_start is null and p_end is null and j.id=p_job))
      and (p_party is null or j.party_id=p_party) and (p_dia is null or pr.dia=p_dia)
  )
  select jsonb_build_object(
    'programs',coalesce((select jsonb_agg(to_jsonb(p) order by job_number,dia,position,id) from programs p),'[]'),
    'entries',coalesce((select jsonb_agg(to_jsonb(e) order by production_date,shift,job_number,dia,id) from entries e),'[]'));
$$;

revoke all on function public.ukm_require_admin(), public.ukm_profile(), public.ukm_edit_profile(text,text),
  public.ukm_managers(), public.ukm_set_manager_enabled(text,boolean),
  public.ukm_save_machine(smallint,text,public.ukm_dia,text,text), public.ukm_archive_machine(smallint),
  public.ukm_set_running(smallint,date,boolean), public.ukm_machine_day(date), public.ukm_calendar(date,date),
  public.ukm_set_booking(smallint,date,boolean) from public,anon,authenticated;
grant execute on function public.ukm_profile(), public.ukm_edit_profile(text,text),
  public.ukm_managers(), public.ukm_set_manager_enabled(text,boolean),
  public.ukm_save_machine(smallint,text,public.ukm_dia,text,text), public.ukm_archive_machine(smallint),
  public.ukm_set_running(smallint,date,boolean), public.ukm_machine_day(date), public.ukm_calendar(date,date),
  public.ukm_set_booking(smallint,date,boolean) to authenticated;
commit;
