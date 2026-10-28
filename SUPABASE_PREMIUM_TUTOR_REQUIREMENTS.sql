-- GURU CONNECT: Premium Tutor Requirements board
-- Separate from Student LRR/coin escrow. Does not modify wallets, coin ledger, or LRR tables.

create table if not exists public.gc_tutor_requirements (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  last_date date not null,
  student_name text not null,
  student_phone text not null,
  student_email text not null,
  search_class text not null,
  course text not null,
  subject_count integer not null check (subject_count between 1 and 6),
  subjects text not null,
  mode text not null check (mode in ('ONLINE','OFFLINE')),
  location text not null,
  fees_budget text not null,
  preferred_timing text,
  status text not null default 'ACTIVE' check (status in ('ACTIVE','CLOSED','EXPIRED'))
);

create index if not exists gc_tutor_requirements_created_at_idx
  on public.gc_tutor_requirements (created_at desc);
create index if not exists gc_tutor_requirements_last_date_idx
  on public.gc_tutor_requirements (last_date, status);

alter table public.gc_tutor_requirements enable row level security;
revoke all on public.gc_tutor_requirements from public, anon, authenticated;

create or replace function public.gc_submit_tutor_requirement(
  p_student_name text,
  p_student_phone text,
  p_student_email text,
  p_search_class text,
  p_course text,
  p_subject_count integer,
  p_subjects text,
  p_mode text,
  p_location text,
  p_fees_budget text,
  p_last_date date,
  p_preferred_timing text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if nullif(trim(p_student_name), '') is null
     or nullif(trim(p_student_phone), '') is null
     or nullif(trim(p_student_email), '') is null
     or nullif(trim(p_search_class), '') is null
     or nullif(trim(p_course), '') is null
     or nullif(trim(p_subjects), '') is null
     or nullif(trim(p_location), '') is null
     or nullif(trim(p_fees_budget), '') is null then
    raise exception 'Please complete all required fields.';
  end if;
  if length(trim(p_student_name)) > 120
     or length(trim(p_student_phone)) > 25
     or length(trim(p_student_email)) > 254
     or length(trim(p_search_class)) > 80
     or length(trim(p_course)) > 120
     or length(trim(p_subjects)) > 600
     or length(trim(p_location)) > 240
     or length(trim(p_fees_budget)) > 100
     or length(coalesce(p_preferred_timing, '')) > 120 then
    raise exception 'One or more fields are too long. Please shorten your entry.';
  end if;
  if trim(p_student_email) !~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$' then
    raise exception 'Please enter a valid email address.';
  end if;
  if p_subject_count is null or p_subject_count < 1 or p_subject_count > 6 then
    raise exception 'Number of subjects must be between 1 and 6.';
  end if;
  if upper(coalesce(p_mode, '')) not in ('ONLINE','OFFLINE') then
    raise exception 'Please select Online or Offline mode.';
  end if;
  if p_last_date is null or p_last_date < current_date then
    raise exception 'Last Date of Requirement cannot be in the past.';
  end if;

  insert into public.gc_tutor_requirements
    (last_date, student_name, student_phone, student_email, search_class, course,
     subject_count, subjects, mode, location, fees_budget, preferred_timing)
  values
    (p_last_date, trim(p_student_name), trim(p_student_phone), trim(p_student_email),
     trim(p_search_class), trim(p_course), p_subject_count, trim(p_subjects),
     upper(trim(p_mode)), trim(p_location), trim(p_fees_budget),
     nullif(trim(coalesce(p_preferred_timing, '')), ''))
  returning id into v_id;

  return jsonb_build_object('success', true, 'requirement_id', v_id);
end;
$$;

create or replace function public.gc_tutor_requirements_list()
returns setof public.gc_tutor_requirements
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Please log in with an eligible Premium Tutor account.';
  end if;

  if not exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and lower(coalesce(p.role::text, '')) = 'tutor'
  ) then
    raise exception 'This section is available only to Tutors.';
  end if;

  if not exists (
    select 1 from public.tutor_profiles t
    where t.user_id = auth.uid()
      and lower(coalesce(t.payment_plan, '')) in ('premium_200','premium_verified_300')
      and upper(coalesce(t.paid_status, '')) = 'PAID'
      and coalesce(t.is_hidden, false) = false
      and coalesce(t.is_disabled, false) = false
  ) then
    raise exception 'TUTOR REQUIREMENTS are available only to active Premium Tutors with confirmed payment (₹200 Premium or ₹300 Premium + Verified Tick).';
  end if;

  return query
    select r.*
    from public.gc_tutor_requirements r
    where r.status = 'ACTIVE'
      and r.last_date >= current_date
    order by r.created_at desc;
end;
$$;

revoke all on function public.gc_submit_tutor_requirement(text,text,text,text,text,integer,text,text,text,text,date,text) from public;
grant execute on function public.gc_submit_tutor_requirement(text,text,text,text,text,integer,text,text,text,text,date,text) to anon, authenticated;
revoke all on function public.gc_tutor_requirements_list() from public, anon;
grant execute on function public.gc_tutor_requirements_list() to authenticated;

notify pgrst, 'reload schema';
