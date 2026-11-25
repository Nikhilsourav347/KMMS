begin;

alter table public.machines add column dia_label text
  check (length(trim(dia_label)) between 1 and 40 and dia_label !~ '[[:cntrl:]]');

create function public.ukm_save_machine_label(
  p_id smallint,p_number text,p_dia_label text,p_type text,p_specifications text
) returns void language plpgsql security definer set search_path='' as $$
declare label text := trim(p_number); machine_name text; machine_type text := trim(coalesce(p_type,''));
  details text := trim(coalesce(p_specifications,'')); next_id smallint;
  diameter text := trim(p_dia_label); numeric_dia public.ukm_dia;
begin
  perform public.ukm_require_admin();
  if label is null or length(label) not between 1 and 40 then
    raise exception 'Enter a machine number.';
  end if;
  if diameter is null or length(diameter) not between 1 and 40 or diameter ~ '[[:cntrl:]]' then
    raise exception 'Enter a DIA label of up to 40 characters.';
  end if;
  if diameter ~ '^[0-9]+$' then
    if diameter::numeric not between 1 and 999 then
      raise exception 'Enter a numeric DIA from 1 to 999.';
    end if;
    numeric_dia := diameter::numeric::public.ukm_dia;
  end if;
  if length(machine_type)>80 or length(details)>360 then raise exception 'Machine type or specifications are too long.'; end if;
  machine_name := case when label ~ '^[0-9]+$' then 'Machine ' || lpad(label,greatest(2,length(label)),'0') else label end;
  perform pg_advisory_xact_lock(91320000);
  if p_id is null then
    next_id := nextval('public.ukm_machine_id_seq'::regclass);
    insert into public.machines(id,name,number,dia,dia_label,type,specifications)
    values(next_id,machine_name,label,numeric_dia,case when numeric_dia is null then diameter end,machine_type,details);
  else
    update public.machines set name=machine_name,number=label,dia=numeric_dia,
      dia_label=case when numeric_dia is null then diameter end,type=machine_type,
      specifications=details,updated_at=clock_timestamp() where id=p_id and removed_at is null;
    if not found then raise exception 'Machine is unavailable.'; end if;
  end if;
exception when unique_violation then
  raise exception 'That machine number has already been registered.';
end;
$$;

revoke all on function public.ukm_save_machine_label(smallint,text,text,text,text) from public, anon, authenticated;
grant execute on function public.ukm_save_machine_label(smallint,text,text,text,text) to authenticated;

commit;
