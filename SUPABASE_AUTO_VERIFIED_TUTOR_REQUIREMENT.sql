-- GURU CONNECT: verified public Tutor Requirement + automatic Premium Tutor delivery.
-- Run once in Supabase SQL Editor AFTER the existing Premium Tutor Requirements
-- and Visitor Premium Tutor Routing setup scripts have been applied.
-- This is separate from Learning Requests (LRR), GURU Coins and escrow.

alter table public.gc_tutor_requirements
  add column if not exists stream text,
  add column if not exists source_inquiry_id uuid,
  add column if not exists requirement_source text not null default 'STUDENT',
  add column if not exists visitor_requirement_details text,
  add column if not exists visitor_type text,
  add column if not exists client_email_verified boolean not null default false,
  add column if not exists email_verified_at timestamptz;

create table if not exists public.gc_tutor_requirement_recipients (
  requirement_id uuid not null references public.gc_tutor_requirements(id) on delete cascade,
  tutor_profile_id uuid not null references public.tutor_profiles(id) on delete cascade,
  delivered_at timestamptz not null default now(),
  primary key (requirement_id, tutor_profile_id)
);
create index if not exists gc_tutor_requirement_recipients_tutor_idx
  on public.gc_tutor_requirement_recipients(tutor_profile_id, delivered_at desc);
alter table public.gc_tutor_requirement_recipients enable row level security;
revoke all on public.gc_tutor_requirement_recipients from public, anon, authenticated;

create or replace function public.gc_submit_verified_tutor_requirement(
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
  v_stream text;
  v_verified_email text;
  v_verified_at timestamptz;
  v_count integer := 0;
  v_details text;
begin
  if auth.uid() is null then
    raise exception 'Please verify your email address with OTP before submitting.';
  end if;

  select lower(u.email), u.email_confirmed_at
    into v_verified_email, v_verified_at
  from auth.users u
  where u.id = auth.uid();

  if v_verified_email is null or v_verified_at is null then
    raise exception 'Your email address is not verified. Please request and verify a new OTP.';
  end if;
  if v_verified_email <> lower(trim(coalesce(p_student_email,''))) then
    raise exception 'The verified email does not match the email entered in this requirement.';
  end if;

  if nullif(trim(p_student_name),'') is null
     or nullif(trim(p_student_phone),'') is null
     or nullif(trim(p_student_email),'') is null
     or nullif(trim(p_search_class),'') is null
     or nullif(trim(p_course),'') is null
     or nullif(trim(p_subjects),'') is null
     or nullif(trim(p_location),'') is null
     or nullif(trim(p_fees_budget),'') is null then
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
     or length(coalesce(p_preferred_timing,'')) > 120 then
    raise exception 'One or more fields are too long. Please shorten your entry.';
  end if;
  if trim(p_student_email) !~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$' then
    raise exception 'Please enter a valid email address.';
  end if;
  if p_subject_count is null or p_subject_count < 1 or p_subject_count > 6 then
    raise exception 'Number of subjects must be between 1 and 6.';
  end if;
  if upper(coalesce(p_mode,'')) not in ('ONLINE','OFFLINE') then
    raise exception 'Please select Online or Offline mode.';
  end if;
  if p_last_date is null or p_last_date < current_date then
    raise exception 'Last Date of Requirement cannot be in the past.';
  end if;

  v_stream := case upper(trim(coalesce(p_course,'')))
    when 'SSC' then 'SSC'
    when 'ARTS' then 'ARTS'
    when 'SCIENCE' then 'SCIENCE'
    when 'COMMERCE' then 'COMMERCE'
    else null
  end;

  v_details := 'CLIENT EMAIL VERIFIED: YES'
    || E'\nVerified at: ' || to_char(v_verified_at at time zone 'UTC','YYYY-MM-DD HH24:MI UTC')
    || E'\nDistribution: Automatic to matching active Premium Tutors'
    || E'\nClass: ' || trim(p_search_class)
    || E'\nCourse: ' || trim(p_course)
    || E'\nSubjects: ' || trim(p_subjects)
    || E'\nMode: ' || upper(trim(p_mode))
    || E'\nLocation: ' || trim(p_location)
    || E'\nBudget: ' || trim(p_fees_budget)
    || E'\nPreferred timing: ' || coalesce(nullif(trim(p_preferred_timing),''),'No preference');

  insert into public.gc_tutor_requirements
    (last_date, student_name, student_phone, student_email, search_class, course,
     subject_count, subjects, mode, location, fees_budget, preferred_timing,
     stream, requirement_source, status, visitor_requirement_details, visitor_type,
     client_email_verified, email_verified_at)
  values
    (p_last_date, trim(p_student_name), trim(p_student_phone), lower(trim(p_student_email)),
     trim(p_search_class), trim(p_course), p_subject_count, trim(p_subjects),
     upper(trim(p_mode)), trim(p_location), trim(p_fees_budget),
     nullif(trim(coalesce(p_preferred_timing,'')),''), v_stream, 'VISITOR', 'ACTIVE',
     v_details, 'Client', true, v_verified_at)
  returning id into v_id;

  -- Deliver only to active paid Premium plans or an explicit Admin Premium ON override.
  -- Explicit Premium OFF, hidden and disabled tutors are excluded.
  insert into public.gc_tutor_requirement_recipients(requirement_id, tutor_profile_id)
  select v_id, t.id
  from public.tutor_profiles t
  where (
      t.premium_badge_override is true
      or (
        t.premium_badge_override is null
        and lower(coalesce(t.payment_plan,'')) in ('premium_200','premium_verified_300')
        and upper(coalesce(t.paid_status,'')) = 'PAID'
      )
    )
    and coalesce(t.is_hidden,false) = false
    and coalesce(t.is_disabled,false) = false
    and (
      exists (
        select 1
        from regexp_split_to_table(trim(p_subjects),'[,;|]') requested_subject
        where nullif(trim(requested_subject),'') is not null
          and regexp_replace(
            lower(coalesce(to_jsonb(t)->>'subject','') || ' ' || coalesce(to_jsonb(t)->>'subjects','')),
            '[^a-z0-9]+',' ','g'
          ) like '%' || regexp_replace(lower(trim(requested_subject)),'[^a-z0-9]+',' ','g') || '%'
      )
    )
    and (
      v_stream is null
      or nullif(trim(coalesce(to_jsonb(t)->>'stream','')),'') is null
      or regexp_replace(lower(coalesce(to_jsonb(t)->>'stream','')),'[^a-z0-9]+',' ','g')
         like '%' || regexp_replace(lower(v_stream),'[^a-z0-9]+',' ','g') || '%'
      or regexp_replace(lower(v_stream),'[^a-z0-9]+',' ','g')
         like '%' || regexp_replace(lower(coalesce(to_jsonb(t)->>'stream','')),'[^a-z0-9]+',' ','g') || '%'
    )
    and (
      nullif(trim(
        coalesce(to_jsonb(t)->>'standard','') || ' ' ||
        coalesce(to_jsonb(t)->>'class','') || ' ' ||
        coalesce(to_jsonb(t)->>'classes_taught','') || ' ' ||
        coalesce(to_jsonb(t)->>'teaching_classes','')
      ),'') is null
      or regexp_replace(
        lower(coalesce(to_jsonb(t)->>'standard','') || ' ' ||
          coalesce(to_jsonb(t)->>'class','') || ' ' ||
          coalesce(to_jsonb(t)->>'classes_taught','') || ' ' ||
          coalesce(to_jsonb(t)->>'teaching_classes','')),
        '[^a-z0-9]+',' ','g'
      ) like '%' || regexp_replace(lower(trim(p_search_class)),'[^a-z0-9]+',' ','g') || '%'
    )
    and (
      nullif(trim(coalesce(to_jsonb(t)->>'course','') || ' ' || coalesce(to_jsonb(t)->>'courses','')),'') is null
      or regexp_replace(
        lower(coalesce(to_jsonb(t)->>'course','') || ' ' || coalesce(to_jsonb(t)->>'courses','')),
        '[^a-z0-9]+',' ','g'
      ) like '%' || regexp_replace(lower(trim(p_course)),'[^a-z0-9]+',' ','g') || '%'
    )
  on conflict do nothing;

  get diagnostics v_count = row_count;

  return jsonb_build_object(
    'success',true,
    'requirement_id',v_id,
    'email_verified',true,
    'matched_tutors',v_count,
    'distribution_status',case when v_count > 0 then 'SENT' else 'NO_MATCHING_PREMIUM_TUTORS' end
  );
end;
$$;

revoke all on function public.gc_submit_verified_tutor_requirement(text,text,text,text,text,integer,text,text,text,text,date,text) from public, anon;
grant execute on function public.gc_submit_verified_tutor_requirement(text,text,text,text,text,integer,text,text,text,text,date,text) to authenticated;

-- Active Tutor Dashboard: show general Student requirements plus visitor requirements
-- specifically delivered to this tutor. Do not expose another tutor's recipient-only posts.
create or replace function public.gc_tutor_requirements_list()
returns setof public.gc_tutor_requirements
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tutor_id uuid;
begin
  if auth.uid() is null then raise exception 'Please log in with an eligible Premium Tutor account.'; end if;
  if not exists (select 1 from public.profiles p where p.id=auth.uid()
    and lower(coalesce(p.role::text,''))='tutor') then
    raise exception 'This section is available only to Tutors.';
  end if;

  select t.id into v_tutor_id
  from public.tutor_profiles t
  where t.user_id=auth.uid()
    and (
      t.premium_badge_override is true
      or (t.premium_badge_override is null
        and lower(coalesce(t.payment_plan,'')) in ('premium_200','premium_verified_300')
        and upper(coalesce(t.paid_status,''))='PAID')
    )
    and coalesce(t.is_hidden,false)=false
    and coalesce(t.is_disabled,false)=false
  limit 1;

  if v_tutor_id is null then
    raise exception 'TUTOR REQUIREMENTS are available only to active Premium Tutors with confirmed payment.';
  end if;

  return query
    select r.* from public.gc_tutor_requirements r
    where r.status='ACTIVE' and r.last_date>=current_date
      and (
        coalesce(r.requirement_source,'STUDENT') <> 'VISITOR'
        or exists (
          select 1 from public.gc_tutor_requirement_recipients rr
          where rr.requirement_id=r.id and rr.tutor_profile_id=v_tutor_id
        )
      )
    order by r.created_at desc;
end;
$$;

-- Tutor lifetime history: include only visitor requirements actually delivered to this tutor.
create or replace function public.gc_tutor_requirement_history_list()
returns setof public.gc_tutor_requirements
language plpgsql
security definer
set search_path = public
as $$
declare v_tutor_id uuid;
begin
  if auth.uid() is null then raise exception 'Please log in with an eligible Premium Tutor account.'; end if;
  select t.id into v_tutor_id from public.tutor_profiles t
  where t.user_id=auth.uid()
    and (
      t.premium_badge_override is true
      or (t.premium_badge_override is null
        and lower(coalesce(t.payment_plan,'')) in ('premium_200','premium_verified_300')
        and upper(coalesce(t.paid_status,''))='PAID')
    )
    and coalesce(t.is_hidden,false)=false
    and coalesce(t.is_disabled,false)=false
  limit 1;
  if v_tutor_id is null then raise exception 'Requirement history is available only to active Premium Tutors.'; end if;

  return query
    select r.* from public.gc_tutor_requirements r
    where coalesce(r.requirement_source,'STUDENT') <> 'VISITOR'
      or exists (
        select 1 from public.gc_tutor_requirement_recipients rr
        where rr.requirement_id=r.id and rr.tutor_profile_id=v_tutor_id
      )
    order by r.created_at desc;
end;
$$;

revoke all on function public.gc_tutor_requirements_list() from public, anon;
grant execute on function public.gc_tutor_requirements_list() to authenticated;
revoke all on function public.gc_tutor_requirement_history_list() from public, anon;
grant execute on function public.gc_tutor_requirement_history_list() to authenticated;

notify pgrst, 'reload schema';
