begin;
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

create function public.ukm_report(p_start date,p_end date,p_shift public.ukm_shift,p_job uuid,p_party uuid,p_dia public.ukm_dia)
returns jsonb language sql stable security invoker set search_path='' as $$
  with entries as (
    select e.*, pr.dia,pr.position as program_position, j.job_number,p.name as party,j.yarn,pr.loop_length,s.name as specification,pr.remarks
    from public.production_entries e
    join public.job_programs pr on pr.id=e.program_id join public.jobs j on j.id=pr.job_id join public.parties p on p.id=j.party_id join public.specifications s on s.id=pr.specification_id
    where (p_start is null or e.production_date>=p_start) and (p_end is null or e.production_date<=p_end)
      and (p_shift is null or e.shift=p_shift) and (p_job is null or j.id=p_job)
      and (p_party is null or j.party_id=p_party) and (p_dia is null or pr.dia=p_dia)
  ), period as (select program_id,sum(quantity_kg) as period_kg from entries group by program_id),
  programs as (
    select pr.*,j.job_number,j.job_date,j.party,j.yarn,coalesce(period.period_kg,0) as period_kg
    from public.ukm_program_totals pr join public.ukm_jobs j on j.id=pr.job_id
    left join period on period.program_id=pr.id
    where (period.program_id is not null or (p_job is not null and p_start is null and p_end is null and j.id=p_job))
      and (p_party is null or j.party_id=p_party) and (p_dia is null or pr.dia=p_dia)
  )
  select jsonb_build_object(
    'programs',coalesce((select jsonb_agg(to_jsonb(p) order by job_number,dia,position,id) from programs p),'[]'),
    'entries',coalesce((select jsonb_agg(to_jsonb(e) order by production_date,shift,job_number,dia,id) from entries e),'[]'));
$$;
revoke all on function public.ukm_report(date,date,public.ukm_shift,uuid,uuid,public.ukm_dia) from public,anon,authenticated;
grant execute on function public.ukm_report(date,date,public.ukm_shift,uuid,uuid,public.ukm_dia) to authenticated;

create extension if not exists pg_cron;
select public.ukm_reset_shift();
-- Check each minute to cover both IST boundaries and recover after scheduler downtime.
select cron.schedule('ukm-shift-rollover','* * * * *','select public.ukm_reset_shift();');
commit;
