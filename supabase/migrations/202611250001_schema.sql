begin;
create type public.ukm_role as enum ('admin','manager');
create type public.ukm_shift as enum ('morning','night');
create type public.ukm_status as enum ('unconfirmed','running','stopped');
create domain public.ukm_dia as integer check (value in (26,28,30,32,34));

create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  full_name text not null check (length(trim(full_name)) between 1 and 120),
  role public.ukm_role not null,
  created_at timestamptz not null default now()
);
create table public.machines (
  id smallint primary key check (id between 1 and 10),
  name text not null unique,
  dia public.ukm_dia,
  updated_at timestamptz not null default now()
);
insert into public.machines(id,name)
select n, 'Machine ' || lpad(n::text,2,'0') from generate_series(1,10) as n;

create table public.parties (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 1 and 120),
  normalized text generated always as (lower(regexp_replace(trim(name), '[[:space:]]+', ' ', 'g'))) stored unique,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users on delete set null
);
create table public.specifications (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 1 and 120),
  normalized text generated always as (lower(regexp_replace(trim(name), '[[:space:]]+', ' ', 'g'))) stored unique,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid() references auth.users on delete set null
);
create table public.jobs (
  id uuid primary key default gen_random_uuid(),
  job_number text not null check (length(trim(job_number)) between 1 and 60),
  job_number_key text generated always as (lower(trim(job_number))) stored unique,
  job_date date not null,
  party_id uuid not null references public.parties,
  yarn text not null check (length(trim(yarn)) between 1 and 240),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default clock_timestamp(),
  created_by uuid default auth.uid() references auth.users on delete set null,
  updated_by uuid default auth.uid() references auth.users on delete set null
);
create table public.job_programs (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.jobs,
  dia public.ukm_dia not null,
  loop_length numeric(12,3) not null check (loop_length > 0),
  ordered_kg numeric(12,3) not null check (ordered_kg > 0),
  specification_id uuid not null references public.specifications,
  remarks text not null default '' check (length(remarks) <= 360),
  position integer not null check (position > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.schedules (
  id uuid primary key default gen_random_uuid(),
  dia public.ukm_dia not null,
  start_date date not null,
  end_date date not null,
  machine_id smallint references public.machines,
  job_id uuid references public.jobs,
  party_id uuid references public.parties,
  remarks text not null default '' check (length(remarks) <= 360),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default clock_timestamp(),
  created_by uuid default auth.uid() references auth.users on delete set null,
  updated_by uuid default auth.uid() references auth.users on delete set null,
  check (end_date >= start_date)
);
create extension if not exists btree_gist with schema extensions;
set local search_path = public, extensions;
alter table public.schedules add constraint schedule_machine_dates_exclude
  exclude using gist (machine_id with =, daterange(start_date,end_date,'[]') with &&)
  where (machine_id is not null);

create table public.production_entries (
  id uuid primary key default gen_random_uuid(),
  program_id uuid not null references public.job_programs,
  production_date date not null,
  shift public.ukm_shift not null,
  quantity_kg numeric(12,3) not null check (quantity_kg >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default clock_timestamp(),
  created_by uuid default auth.uid() references auth.users on delete set null,
  updated_by uuid default auth.uid() references auth.users on delete set null,
  unique (program_id,production_date,shift)
);
create table public.machine_status (
  machine_id smallint primary key references public.machines,
  shift_date date not null,
  shift public.ukm_shift not null,
  status public.ukm_status not null default 'unconfirmed',
  job_id uuid references public.jobs,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users on delete set null
);
create table public.machine_status_history (
  machine_id smallint not null references public.machines,
  shift_date date not null,
  shift public.ukm_shift not null,
  status public.ukm_status not null,
  dia public.ukm_dia,
  job_number text,
  party_name text,
  updated_at timestamptz not null,
  updated_by uuid references auth.users on delete set null,
  primary key (machine_id,shift_date,shift)
);
create table public.audit_logs (
  id bigint generated always as identity primary key,
  actor uuid references auth.users on delete set null,
  table_name text not null,
  operation text not null,
  before_row jsonb,
  after_row jsonb,
  recorded_at timestamptz not null default now()
);
create table public.mill_settings (
  singleton boolean primary key default true check (singleton),
  allow_overproduction boolean not null default false
);
insert into public.mill_settings default values;
create index jobs_party_date_idx on public.jobs(party_id,job_date desc);
create index jobs_date_idx on public.jobs(job_date desc,id);
create index programs_job_idx on public.job_programs(job_id,position);
create index schedules_window_idx on public.schedules(start_date,end_date);
create index production_day_idx on public.production_entries(production_date,shift);
create index history_shift_idx on public.machine_status_history(shift_date desc,shift);
create index audit_date_idx on public.audit_logs(recorded_at desc);

create function public.ukm_role_for_user() returns public.ukm_role
language sql stable security definer set search_path = '' as $$
  select role from public.profiles where id = auth.uid()
$$;
revoke all on function public.ukm_role_for_user() from public, anon, authenticated;
grant execute on function public.ukm_role_for_user() to authenticated;

create policy own_profile on public.profiles for select to authenticated using (id = auth.uid());
alter table public.profiles enable row level security;
revoke all on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;

do $$
declare t text;
begin
  foreach t in array array['machines','parties','specifications','jobs','job_programs','schedules','production_entries','machine_status','machine_status_history','audit_logs','mill_settings'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    if t not in ('audit_logs','mill_settings','machine_status_history') then
      execute format('grant select on public.%I to authenticated', t);
      execute format('create policy staff_read on public.%I for select to authenticated using ((select public.ukm_role_for_user()) is not null)', t);
    elsif t = 'machine_status_history' then
      execute 'grant select on public.machine_status_history to authenticated';
      execute $policy$create policy admin_history on public.machine_status_history for select to authenticated using ((select public.ukm_role_for_user()) = 'admin')$policy$;
    end if;
  end loop;
end
$$;

create function public.ukm_audit() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.audit_logs(actor,table_name,operation,before_row,after_row)
  values (auth.uid(),tg_table_name,tg_op,
    case when tg_op <> 'INSERT' then to_jsonb(old) end,
    case when tg_op <> 'DELETE' then to_jsonb(new) end);
  return coalesce(new,old);
end
$$;
revoke all on function public.ukm_audit() from public, anon, authenticated;
do $$
declare t text;
begin
  foreach t in array array['profiles','machines','jobs','job_programs','schedules','production_entries','mill_settings'] loop
    execute format('create trigger record_audit after insert or update or delete on public.%I for each row execute function public.ukm_audit()', t);
  end loop;
end
$$;

alter publication supabase_realtime add table public.profiles, public.machines, public.machine_status,
  public.machine_status_history, public.schedules, public.jobs, public.job_programs,
  public.parties, public.specifications, public.production_entries;
commit;
