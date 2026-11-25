-- Apply migration 006 first. The final ROLLBACK previews the exact candidates.
-- Change the final statement to COMMIT only after reviewing the returned rows.
begin;
select pg_advisory_xact_lock(35680830);
select pg_advisory_xact_lock(91320000);

create temporary table ukm_cleanup_machines on commit drop as
select id, name from public.machines
where id between 1 and 10
  and name = 'Machine ' || lpad(id::text, 2, '0')
  and number is null and dia is null
  and type = '' and specifications = '' and removed_at is not null
for update;

delete from ukm_cleanup_machines where public.ukm_machine_has_history(id);

select id, name from ukm_cleanup_machines order by id;
delete from public.machine_status_history where machine_id in (select id from ukm_cleanup_machines);
delete from public.machine_status where machine_id in (select id from ukm_cleanup_machines);
delete from public.machines where id in (select id from ukm_cleanup_machines)
returning id, name;

rollback;
