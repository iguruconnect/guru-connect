-- GURU CONNECT: route public visitor inquiries to matching active Premium Tutors.
-- Separate from Learning Requests (LRR), coin escrow and coin ledger.
-- Run this file ONCE in Supabase SQL Editor after deploying the matching admin/dashboard changes.

alter table public.gc_tutor_inquiries
  add column if not exists stream text,
  add column if not exists requirement_details text,
  add column if not exists location text,
  add column if not exists visitor_type text not null default 'Visitor';

alter table public.gc_tutor_requirements
  add column if not exists stream text,
  add column if not exists source_inquiry_id uuid,
  add column if not exists requirement_source text not null default 'STUDENT';

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


create or replace function public.gc_submit_tutor_inquiry(
  p_visitor_name text, p_visitor_phone text, p_visitor_email text,
  p_tutor_id uuid, p_tutor_name text, p_search_class text default null,
  p_course text default null, p_subjects text default null, p_stream text default null
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare v_id uuid;
begin
  if nullif(trim(p_visitor_name),'') is null or nullif(trim(p_visitor_phone),'') is null
     or nullif(trim(p_visitor_email),'') is null then
    raise exception 'Name, phone number and email are required.';
  end if;
  if p_tutor_id is null or nullif(trim(p_tutor_name),'') is null then
    raise exception 'A tutor must be selected for the inquiry.';
  end if;
  if not exists (select 1 from public.tutor_profiles t where t.id=p_tutor_id
    and coalesce(t.is_hidden,false)=false and coalesce(t.is_disabled,false)=false
    and (lower(coalesce(t.registration_status::text,''))='approved'
      or coalesce(t.registration_approved,false)=true
      or lower(coalesce(t.registration_approval_status::text,''))='approved')) then
    raise exception 'This tutor is not currently available for inquiry.';
  end if;
  insert into public.gc_tutor_inquiries
    (visitor_name,visitor_phone,visitor_email,tutor_id,tutor_name,search_class,course,subjects,stream)
  values (trim(p_visitor_name),trim(p_visitor_phone),trim(p_visitor_email),p_tutor_id,
    trim(p_tutor_name),nullif(trim(p_search_class),''),nullif(trim(p_course),''),
    nullif(trim(p_subjects),''),nullif(trim(p_stream),''))
  returning id into v_id;
  return jsonb_build_object('success',true,'inquiry_id',v_id);
end;
$$;
revoke all on function public.gc_submit_tutor_inquiry(text,text,text,uuid,text,text,text,text,text) from public;
grant execute on function public.gc_submit_tutor_inquiry(text,text,text,uuid,text,text,text,text,text) to anon, authenticated;

create or replace function public.gc_admin_send_visitor_requirement_to_premium_tutors(p_inquiry_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v public.gc_tutor_inquiries%rowtype;
  v_req uuid;
  v_count integer := 0;
  v_class text;
  v_course text;
  v_stream text;
  v_subjects text;
begin
  if auth.uid() is null or not (
    exists (select 1 from public.profiles p where p.id = auth.uid()
      and lower(coalesce(p.role::text,'')) in ('admin','staff'))
    or lower(coalesce(auth.jwt()->'user_metadata'->>'role','')) in ('admin','staff')
    or lower(coalesce(auth.jwt()->'app_metadata'->>'role','')) in ('admin','staff')
    or lower(coalesce(auth.jwt()->>'email','')) = 'guruconnect.in@gmail.com'
    or lower(coalesce(auth.jwt()->'user_metadata'->>'is_staff','')) = 'true'
    or lower(coalesce(auth.jwt()->'app_metadata'->>'is_staff','')) = 'true'
  ) then raise exception 'Admin/Staff authorization required.'; end if;

  select * into v from public.gc_tutor_inquiries where id = p_inquiry_id for update;
  if not found then raise exception 'Visitor inquiry not found.'; end if;
  if exists (select 1 from public.gc_tutor_requirements where source_inquiry_id = p_inquiry_id) then
    raise exception 'This visitor requirement has already been sent to matching Premium Tutors.';
  end if;

  v_class := coalesce(nullif(trim(v.search_class),''),'Not specified');
  v_course := coalesce(nullif(trim(v.course),''),'Not specified');
  v_stream := coalesce(nullif(trim(v.stream),''),'Not specified');
  v_subjects := coalesce(nullif(trim(v.subjects),''),'Not specified');

  insert into public.gc_tutor_requirements
    (last_date, student_name, student_phone, student_email, search_class, course,
     subject_count, subjects, mode, location, fees_budget, preferred_timing,
     stream, source_inquiry_id, requirement_source, status)
  values
    (current_date + 30, coalesce(nullif(trim(v.visitor_name),''),'Visitor'),
     coalesce(nullif(trim(v.visitor_phone),''),'Not provided'),
     coalesce(nullif(trim(v.visitor_email),''),'not-provided@example.invalid'),
     v_class, v_course,
     greatest(1, least(6, array_length(regexp_split_to_array(v_subjects, '\\s*[,;|]\\s*'),1))),
     v_subjects, 'ONLINE', coalesce(nullif(trim(v.location),''),'To be confirmed'),
     'To be discussed directly', null, v_stream, v.id, 'VISITOR', 'ACTIVE')
  returning id into v_req;

  insert into public.gc_tutor_requirement_recipients(requirement_id, tutor_profile_id)
  select v_req, t.id
  from public.tutor_profiles t
  where lower(coalesce(t.payment_plan,'')) in ('premium_200','premium_verified_300')
    and upper(coalesce(t.paid_status,'')) = 'PAID'
    and coalesce(t.is_hidden,false) = false
    and coalesce(t.is_disabled,false) = false
    and (
      lower(coalesce(to_jsonb(t)->>'stream','')) like '%'||lower(v_stream)||'%'
      or v_stream = 'Not specified'
    )
    and (
      lower(coalesce(to_jsonb(t)->>'subject','') || ' ' || coalesce(to_jsonb(t)->>'subjects',''))
        like '%'||lower(split_part(v_subjects,',',1))||'%'
      or lower(coalesce(to_jsonb(t)->>'subject','') || ' ' || coalesce(to_jsonb(t)->>'subjects',''))
        like '%'||lower(v_subjects)||'%'
    )
    and (
      lower(coalesce(to_jsonb(t)->>'standard','') || ' ' || coalesce(to_jsonb(t)->>'class','') || ' ' || coalesce(to_jsonb(t)->>'classes_taught',''))
        like '%'||lower(v_class)||'%'
      or lower(coalesce(to_jsonb(t)->>'teaching_classes','')) like '%'||lower(v_class)||'%'
    )
  on conflict do nothing;

  get diagnostics v_count = row_count;
  if v_count = 0 then
    delete from public.gc_tutor_requirements where id = v_req;
    raise exception 'No active Premium Tutor matched this Standard, Stream and Subject. Please check the inquiry details/profile matching before sending.';
  end if;

  update public.gc_tutor_inquiries
    set status = 'FORWARDED',
        forwarded_to = v_count::text || ' matching Premium Tutor(s)',
        forwarded_at = now()
  where id = p_inquiry_id;

  return jsonb_build_object('success',true,'requirement_id',v_req,'matched_tutors',v_count);
end;
$$;

create or replace function public.gc_tutor_requirements_list()
returns setof public.gc_tutor_requirements
language plpgsql
security definer
set search_path = public
as $$
declare v_tutor_id uuid;
begin
  if auth.uid() is null then raise exception 'Please log in with an eligible Premium Tutor account.'; end if;
  if not exists (select 1 from public.profiles p where p.id = auth.uid()
    and lower(coalesce(p.role::text,'')) = 'tutor') then
    raise exception 'This section is available only to Tutors.';
  end if;
  select t.id into v_tutor_id from public.tutor_profiles t
  where t.user_id = auth.uid()
    and lower(coalesce(t.payment_plan,'')) in ('premium_200','premium_verified_300')
    and upper(coalesce(t.paid_status,'')) = 'PAID'
    and coalesce(t.is_hidden,false) = false
    and coalesce(t.is_disabled,false) = false
  limit 1;
  if v_tutor_id is null then
    raise exception 'TUTOR REQUIREMENTS are available only to active Premium Tutors with confirmed payment (₹200 Premium or ₹300 Premium + Verified Tick).';
  end if;

  return query
    select r.* from public.gc_tutor_requirements r
    where r.status = 'ACTIVE' and r.last_date >= current_date
      and (
        coalesce(r.requirement_source,'STUDENT') <> 'VISITOR'
        or exists (select 1 from public.gc_tutor_requirement_recipients x
          where x.requirement_id = r.id and x.tutor_profile_id = v_tutor_id)
      )
    order by r.created_at desc;
end;
$$;

revoke all on function public.gc_admin_send_visitor_requirement_to_premium_tutors(uuid) from public, anon;
grant execute on function public.gc_admin_send_visitor_requirement_to_premium_tutors(uuid) to authenticated;
revoke all on function public.gc_tutor_requirements_list() from public, anon;
grant execute on function public.gc_tutor_requirements_list() to authenticated;

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
  where t.user_id = auth.uid()
    and lower(coalesce(t.payment_plan,'')) in ('premium_200','premium_verified_300')
    and upper(coalesce(t.paid_status,'')) = 'PAID'
    and coalesce(t.is_hidden,false) = false
    and coalesce(t.is_disabled,false) = false
  limit 1;
  if v_tutor_id is null then raise exception 'Requirement history is available only to active Premium Tutors.'; end if;
  return query select r.* from public.gc_tutor_requirements r
   where (coalesce(r.requirement_source,'STUDENT') <> 'VISITOR'
      or exists (select 1 from public.gc_tutor_requirement_recipients x
       where x.requirement_id=r.id and x.tutor_profile_id=v_tutor_id))
   order by r.created_at desc;
end;
$$;
revoke all on function public.gc_tutor_requirement_history_list() from public, anon;
grant execute on function public.gc_tutor_requirement_history_list() to authenticated;


-- Admin inquiry history: show each inquiry and the actual Premium Tutor recipient(s).
-- This is a read-only history view; it does not change LRRs, escrow, or coin balances.
create or replace function public.gc_admin_tutor_inquiry_history()
returns table (
  inquiry_id uuid,
  inquiry_received timestamptz,
  visitor_name text,
  search_class text,
  course text,
  stream text,
  subjects text,
  inquiry_status text,
  forwarded_at timestamptz,
  tutor_name text,
  tutor_email text,
  delivered_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not (
    exists (select 1 from public.profiles p where p.id = auth.uid()
      and lower(coalesce(p.role::text,'')) in ('admin','staff'))
    or lower(coalesce(auth.jwt()->'user_metadata'->>'role','')) in ('admin','staff')
    or lower(coalesce(auth.jwt()->'app_metadata'->>'role','')) in ('admin','staff')
    or lower(coalesce(auth.jwt()->>'email','')) = 'guruconnect.in@gmail.com'
    or lower(coalesce(auth.jwt()->'user_metadata'->>'is_staff','')) = 'true'
    or lower(coalesce(auth.jwt()->'app_metadata'->>'is_staff','')) = 'true'
  ) then
    raise exception 'Admin/Staff authorization required.';
  end if;

  return query
  select
    i.id,
    i.created_at,
    i.visitor_name,
    i.search_class,
    i.course,
    i.stream,
    i.subjects,
    i.status,
    i.forwarded_at,
    coalesce(
      nullif(to_jsonb(t)->>'full_name',''),
      nullif(to_jsonb(t)->>'name',''),
      nullif(to_jsonb(t)->>'display_name',''),
      nullif(to_jsonb(p)->>'full_name',''),
      nullif(to_jsonb(p)->>'name',''),
      nullif(to_jsonb(p)->>'display_name',''),
      'Premium Tutor'
    )::text,
    coalesce(
      nullif(to_jsonb(t)->>'email',''),
      nullif(to_jsonb(p)->>'email',''),
      ''
    )::text,
    rr.delivered_at
  from public.gc_tutor_inquiries i
  left join public.gc_tutor_requirements r on r.source_inquiry_id = i.id
  left join public.gc_tutor_requirement_recipients rr on rr.requirement_id = r.id
  left join public.tutor_profiles t on t.id = rr.tutor_profile_id
  left join public.profiles p on p.id = t.user_id
  order by i.created_at desc, rr.delivered_at asc nulls last;
end;
$$;

revoke all on function public.gc_admin_tutor_inquiry_history() from public, anon;
grant execute on function public.gc_admin_tutor_inquiry_history() to authenticated;

notify pgrst, 'reload schema';
