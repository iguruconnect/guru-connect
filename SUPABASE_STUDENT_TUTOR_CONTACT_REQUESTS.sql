-- GURU CONNECT: Admin lifetime requirement history + secure Student-to-Tutor contact requests.
-- Run this NEW migration once in Supabase SQL Editor after deploying matching website code.
-- This migration does not update payment flags, verification flags, GURU Coins, wallets,
-- coin ledger, Learning Requests (LRR), or existing inquiry/requirement records.

begin;

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Admin lifetime history for Tutor Requirements (including visitor requirements).
-- Existing gc_tutor_requirements rows are read only; nothing is deleted or rewritten.
-- ---------------------------------------------------------------------------
create or replace function public.gc_admin_tutor_requirement_history()
returns setof public.gc_tutor_requirements
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and lower(coalesce(p.role::text,'')) in ('admin','staff')
    )
    or lower(coalesce(auth.jwt()->'user_metadata'->>'role','')) in ('admin','staff')
    or lower(coalesce(auth.jwt()->'app_metadata'->>'role','')) in ('admin','staff')
    or lower(coalesce(auth.jwt()->>'email','')) = 'guruconnect.in@gmail.com'
    or lower(coalesce(auth.jwt()->'user_metadata'->>'is_staff','')) = 'true'
    or lower(coalesce(auth.jwt()->'app_metadata'->>'is_staff','')) = 'true'
  ) then
    raise exception 'Admin/Staff authorization required.';
  end if;

  return query
    select r.*
    from public.gc_tutor_requirements r
    order by r.created_at desc;
end;
$$;

revoke all on function public.gc_admin_tutor_requirement_history() from public, anon;
grant execute on function public.gc_admin_tutor_requirement_history() to authenticated;

-- ---------------------------------------------------------------------------
-- Student-to-Tutor contact request log.
-- Personal contact information is snapshotted for Admin handling only.
-- No student phone/email is returned to the tutor through this RPC.
-- ---------------------------------------------------------------------------
create table if not exists public.gc_student_tutor_contact_requests (
  id uuid primary key default gen_random_uuid(),
  requested_at timestamptz not null default now(),
  student_user_id uuid not null,
  student_name text not null,
  student_email text,
  student_phone text,
  tutor_profile_id uuid not null,
  tutor_user_id uuid not null,
  tutor_name text not null,
  tutor_email text,
  status text not null default 'PENDING'
    check (status in ('PENDING','CONTACTED','CONNECTED','DECLINED','CLOSED')),
  admin_note text,
  updated_at timestamptz not null default now()
);

create index if not exists gc_student_tutor_contact_requests_date_idx
  on public.gc_student_tutor_contact_requests(requested_at desc);
create index if not exists gc_student_tutor_contact_requests_student_idx
  on public.gc_student_tutor_contact_requests(student_user_id, requested_at desc);
create index if not exists gc_student_tutor_contact_requests_tutor_idx
  on public.gc_student_tutor_contact_requests(tutor_user_id, requested_at desc);

alter table public.gc_student_tutor_contact_requests enable row level security;
revoke all on public.gc_student_tutor_contact_requests from public, anon, authenticated;

-- Registered Student only. Eligibility is rechecked on the server at request time:
-- paid Premium plan + PAID + Verified Tick + approved + visible + enabled.
create or replace function public.gc_student_request_tutor_contact(p_tutor_profile_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_id uuid := auth.uid();
  v_student_name text;
  v_student_email text;
  v_student_phone text;
  v_tutor_user_id uuid;
  v_tutor_name text;
  v_tutor_email text;
  v_request_id uuid;
begin
  if v_student_id is null then
    raise exception 'Please log in with your registered Student account.';
  end if;

  if not exists (
    select 1 from public.profiles p
    where p.id = v_student_id
      and lower(coalesce(p.role::text,'')) = 'student'
  ) then
    raise exception 'MESSAGE TUTOR is available only to registered Students.';
  end if;

  select
    coalesce(nullif(trim(p.full_name),''), nullif(trim(s.name),''), 'Student'),
    coalesce(nullif(trim(p.email),''), nullif(trim(s.email),''), lower(auth.jwt()->>'email')),
    coalesce(nullif(trim(p.phone),''), nullif(trim(s.phone),''))
  into v_student_name, v_student_email, v_student_phone
  from public.profiles p
  left join public.student_profiles s on s.user_id = p.id
  where p.id = v_student_id;

  if v_student_name is null then
    raise exception 'Student profile not found. Please complete Student registration.';
  end if;

  select
    t.user_id,
    coalesce(nullif(trim(t.name),''), nullif(trim(p.full_name),''), 'Tutor'),
    coalesce(nullif(trim(p.email),''), nullif(trim(to_jsonb(t)->>'email'),'' ))
  into v_tutor_user_id, v_tutor_name, v_tutor_email
  from public.tutor_profiles t
  join public.profiles p on p.id = t.user_id
  where t.id = p_tutor_profile_id
    and lower(coalesce(p.role::text,'')) = 'tutor'
    and lower(coalesce(t.payment_plan,'')) in ('premium_200','premium_verified_300')
    and upper(coalesce(t.paid_status,'')) = 'PAID'
    and coalesce(t.verified,false) = true
    and coalesce(t.is_hidden,false) = false
    and coalesce(t.is_disabled,false) = false
    and (
      lower(coalesce(t.registration_status::text,'')) = 'approved'
      or coalesce(t.registration_approved,false) = true
      or lower(coalesce(t.registration_approval_status::text,'')) = 'approved'
    )
  limit 1;

  if v_tutor_user_id is null then
    raise exception 'This tutor is not currently eligible. MESSAGE TUTOR is available only for active Premium Tutors with Verified Tick.';
  end if;

  -- Serialize repeat clicks for this student/tutor pair, then apply a 24-hour
  -- duplicate guard. A later request is allowed after the cooldown.
  perform pg_advisory_xact_lock(
    hashtextextended(v_student_id::text || ':' || v_tutor_user_id::text, 0)
  );

  if exists (
    select 1
    from public.gc_student_tutor_contact_requests r
    where r.student_user_id = v_student_id
      and r.tutor_user_id = v_tutor_user_id
      and r.requested_at >= now() - interval '24 hours'
      and r.status in ('PENDING','CONTACTED','CONNECTED')
  ) then
    raise exception 'You have already sent a contact request to this tutor recently. Please wait 24 hours before sending another.';
  end if;

  insert into public.gc_student_tutor_contact_requests (
    student_user_id, student_name, student_email, student_phone,
    tutor_profile_id, tutor_user_id, tutor_name, tutor_email
  ) values (
    v_student_id, v_student_name, v_student_email, v_student_phone,
    p_tutor_profile_id, v_tutor_user_id, v_tutor_name, v_tutor_email
  )
  returning id into v_request_id;

  return jsonb_build_object(
    'success', true,
    'request_id', v_request_id,
    'message', 'Your contact request has been sent to Admin for assistance.'
  );
end;
$$;

revoke all on function public.gc_student_request_tutor_contact(uuid) from public, anon;
grant execute on function public.gc_student_request_tutor_contact(uuid) to authenticated;

-- Admin-only date-wise history. Contact details remain inside this Admin RPC.
create or replace function public.gc_admin_student_tutor_contact_history()
returns table (
  request_id uuid,
  requested_at timestamptz,
  student_user_id uuid,
  student_name text,
  student_email text,
  student_phone text,
  tutor_profile_id uuid,
  tutor_user_id uuid,
  tutor_name text,
  tutor_email text,
  request_status text,
  admin_note text,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and lower(coalesce(p.role::text,'')) in ('admin','staff')
    )
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
      r.id, r.requested_at, r.student_user_id, r.student_name,
      r.student_email, r.student_phone, r.tutor_profile_id,
      r.tutor_user_id, r.tutor_name, r.tutor_email,
      r.status, r.admin_note, r.updated_at
    from public.gc_student_tutor_contact_requests r
    order by r.requested_at desc;
end;
$$;

revoke all on function public.gc_admin_student_tutor_contact_history() from public, anon;
grant execute on function public.gc_admin_student_tutor_contact_history() to authenticated;

-- Admin-only status/note update for the request log.
create or replace function public.gc_admin_update_student_tutor_contact_request(
  p_request_id uuid,
  p_status text,
  p_admin_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_status text := upper(trim(coalesce(p_status,'')));
begin
  if auth.uid() is null or not (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and lower(coalesce(p.role::text,'')) in ('admin','staff')
    )
    or lower(coalesce(auth.jwt()->'user_metadata'->>'role','')) in ('admin','staff')
    or lower(coalesce(auth.jwt()->'app_metadata'->>'role','')) in ('admin','staff')
    or lower(coalesce(auth.jwt()->>'email','')) = 'guruconnect.in@gmail.com'
    or lower(coalesce(auth.jwt()->'user_metadata'->>'is_staff','')) = 'true'
    or lower(coalesce(auth.jwt()->'app_metadata'->>'is_staff','')) = 'true'
  ) then
    raise exception 'Admin/Staff authorization required.';
  end if;

  if v_status not in ('PENDING','CONTACTED','CONNECTED','DECLINED','CLOSED') then
    raise exception 'Invalid contact request status.';
  end if;

  update public.gc_student_tutor_contact_requests
     set status = v_status,
         admin_note = nullif(trim(coalesce(p_admin_note,'')),''),
         updated_at = now()
   where id = p_request_id;

  if not found then raise exception 'Contact request not found.'; end if;
  return jsonb_build_object('success',true,'request_id',p_request_id,'status',v_status);
end;
$$;

revoke all on function public.gc_admin_update_student_tutor_contact_request(uuid,text,text) from public, anon;
grant execute on function public.gc_admin_update_student_tutor_contact_request(uuid,text,text) to authenticated;

notify pgrst, 'reload schema';

commit;
