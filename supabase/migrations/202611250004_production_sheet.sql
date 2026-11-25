begin;
create function public.ukm_production_sheet(p_job uuid,p_date date,p_shift public.ukm_shift)
returns jsonb language sql stable security invoker set search_path='' as $$
  select jsonb_build_object(
    'job',(select to_jsonb(j) from public.ukm_jobs j where j.id=p_job),
    'programs',coalesce((
      select jsonb_agg(to_jsonb(p) || jsonb_build_object(
        'shift_kg',e.quantity_kg,'shift_version',e.updated_at,
        'previous_kg',p.produced_kg-coalesce(e.quantity_kg,0)
      ) order by p.dia,p.position)
      from public.ukm_program_totals p left join public.production_entries e
        on e.program_id=p.id and e.production_date=p_date and e.shift=p_shift
      where p.job_id=p_job
    ),'[]'));
$$;
revoke all on function public.ukm_production_sheet(uuid,date,public.ukm_shift) from public,anon,authenticated;
grant execute on function public.ukm_production_sheet(uuid,date,public.ukm_shift) to authenticated;
commit;
