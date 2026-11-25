begin;

-- Keep machine identifiers unique across archived and permanently deleted rows.
lock table public.machines in share row exclusive mode;
create sequence public.ukm_machine_id_seq as smallint owned by public.machines.id;
select setval('public.ukm_machine_id_seq', coalesce(max(id), 0) + 1, false)
from public.machines;
revoke all on sequence public.ukm_machine_id_seq from public, anon, authenticated;

create or replace function public.ukm_save_machine(
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
    next_id := nextval('public.ukm_machine_id_seq'::regclass);
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

create or replace function public.ukm_reset_shift(p_time timestamptz default clock_timestamp()) returns void
language plpgsql security definer set search_path='' as $$
declare target record; prior record; next_date date; next_shift public.ukm_shift;
begin
  perform pg_advisory_xact_lock(35680830);
  select * into target from public.ukm_shift_at(p_time);
  for prior in select s.* from public.machine_status s
    join public.machines m on m.id = s.machine_id and m.removed_at is null
    where (s.shift_date,s.shift) < (target.shift_date,target.shift) order by s.machine_id
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
  from public.machines where removed_at is null
  on conflict(machine_id) do update
    set shift_date=excluded.shift_date,shift=excluded.shift,status='unconfirmed',job_id=null,
      updated_at=excluded.updated_at,updated_by=null
    where (public.machine_status.shift_date,public.machine_status.shift) < (excluded.shift_date,excluded.shift);
end
$$;

-- Callers lock the machine and coordinate with the shift rollover first.
create function public.ukm_machine_has_history(p_id smallint) returns boolean
language sql stable set search_path = '' as $$
  select exists (select from public.schedules where machine_id = p_id)
    or exists (select from public.daily_machine_status where machine_id = p_id)
    or exists (
      select from public.machine_status where machine_id = p_id
        and (status <> 'unconfirmed' or job_id is not null or updated_by is not null)
    )
    or exists (
      select from public.machine_status_history where machine_id = p_id
        and (status <> 'unconfirmed' or job_number is not null
          or party_name is not null or updated_by is not null)
    );
$$;
revoke all on function public.ukm_machine_has_history(smallint) from public, anon, authenticated;

-- True denotes permanent deletion. False denotes archiving.
create function public.ukm_remove_machine(p_id smallint) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  perform public.ukm_require_admin();
  perform pg_advisory_xact_lock(35680830);
  perform 1 from public.machines where id = p_id for update;
  if not found then raise exception 'Machine is unavailable.'; end if;

  if public.ukm_machine_has_history(p_id) then
    update public.machines
      set removed_at = clock_timestamp(), updated_at = clock_timestamp()
      where id = p_id and removed_at is null;
    return false;
  end if;

  delete from public.machine_status_history where machine_id = p_id;
  delete from public.machine_status where machine_id = p_id;
  delete from public.machines where id = p_id;
  return true;
end;
$$;
revoke all on function public.ukm_remove_machine(smallint) from public, anon, authenticated;
grant execute on function public.ukm_remove_machine(smallint) to authenticated;

-- Auth writes app metadata on the server. User-editable metadata never assigns roles.
create function public.ukm_provision_staff_profile() returns trigger
language plpgsql security definer set search_path = '' as $$
declare staff jsonb := new.raw_app_meta_data->'ukm_staff_provisioning';
begin
  if staff is not null then
    insert into public.profiles (id, full_name, phone, role)
      values (new.id, staff->>'full_name', coalesce(staff->>'phone', ''),
        (staff->>'role')::public.ukm_role);
  end if;
  return new;
end;
$$;
revoke all on function public.ukm_provision_staff_profile() from public, anon, authenticated;

create trigger ukm_provision_staff_profile after insert on auth.users
  for each row execute function public.ukm_provision_staff_profile();

commit;
