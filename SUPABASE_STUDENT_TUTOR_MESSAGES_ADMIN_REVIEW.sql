-- GURU CONNECT: Admin-reviewed Student -> Tutor messages.
-- Separate from GURU Coins, wallets, ledger and Learning Requests (LRR).
-- Apply once in Supabase SQL Editor after deploying the matching website PR.

begin;
create extension if not exists pgcrypto;

create table if not exists public.gc_student_tutor_messages (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  student_user_id uuid not null,
  student_profile_id uuid,
  student_name text not null,
  student_email text,
  student_phone text,
  student_profile_snapshot jsonb not null default '{}'::jsonb,
  tutor_profile_id uuid not null,
  tutor_user_id uuid not null,
  tutor_name text not null,
  message text not null check (char_length(trim(message)) between 1 and 3000),
  status text not null default 'PENDING_ADMIN'
    check (status in ('PENDING_ADMIN','SENT_TO_TUTOR','REJECTED')),
  reviewed_by uuid,
  reviewed_at timestamptz,
  forwarded_at timestamptz,
  admin_note text
);

create index if not exists gc_student_tutor_messages_created_idx
  on public.gc_student_tutor_messages(created_at desc);
create index if not exists gc_student_tutor_messages_status_idx
  on public.gc_student_tutor_messages(status,created_at desc);
create index if not exists gc_student_tutor_messages_student_idx
  on public.gc_student_tutor_messages(student_user_id,created_at desc);
create index if not exists gc_student_tutor_messages_tutor_idx
  on public.gc_student_tutor_messages(tutor_user_id,created_at desc);

alter table public.gc_student_tutor_messages enable row level security;
revoke all on public.gc_student_tutor_messages from public, anon, authenticated;

create or replace function public.gc_student_submit_tutor_message(
  p_tutor_profile_id uuid,
  p_message text
) returns jsonb
language plpgsql security definer
set search_path=public
as $$
declare
  v_uid uuid := auth.uid();
  v_student jsonb;
  v_tutor_user_id uuid;
  v_tutor_name text;
  v_student_name text;
  v_student_email text;
  v_student_phone text;
  v_profile_id uuid;
  v_id uuid;
  v_msg text := trim(coalesce(p_message,''));
begin
  if v_uid is null then raise exception 'Please log in with your registered Student account.'; end if;
  if char_length(v_msg)<1 or char_length(v_msg)>3000 then
    raise exception 'Please enter a message of 1 to 3000 characters.';
  end if;
  if not exists(select 1 from public.profiles p where p.id=v_uid and lower(coalesce(p.role::text,''))='student') then
    raise exception 'SEND MESSAGE is available only to registered Students.';
  end if;

  select to_jsonb(p)||coalesce(to_jsonb(s),'{}'::jsonb),
         coalesce(nullif(trim(p.full_name),''),nullif(trim(s.name),''),'Student'),
         coalesce(nullif(trim(p.email),''),nullif(trim(s.email),''),lower(auth.jwt()->>'email')),
         coalesce(nullif(trim(p.phone),''),nullif(trim(s.phone),'')),
         s.id
    into v_student,v_student_name,v_student_email,v_student_phone,v_profile_id
  from public.profiles p
  left join public.student_profiles s on s.user_id=p.id
  where p.id=v_uid;

  if v_student is null then raise exception 'Student profile not found. Please complete registration.'; end if;

  select t.user_id,
         coalesce(nullif(trim(t.name),''),nullif(trim(p.full_name),''),'Tutor')
    into v_tutor_user_id,v_tutor_name
  from public.tutor_profiles t
  join public.profiles p on p.id=t.user_id
  where t.id=p_tutor_profile_id
    and lower(coalesce(p.role::text,''))='tutor'
    and coalesce(t.is_hidden,false)=false
    and coalesce(t.is_disabled,false)=false
    and (
      lower(coalesce(t.registration_status::text,''))='approved'
      or coalesce(t.registration_approved,false)=true
      or lower(coalesce(t.registration_approval_status::text,''))='approved'
    )
  limit 1;

  if v_tutor_user_id is null then raise exception 'This tutor profile is not currently available.'; end if;

  perform pg_advisory_xact_lock(hashtextextended(v_uid::text||':'||v_tutor_user_id::text,0));
  if exists(
    select 1 from public.gc_student_tutor_messages m
    where m.student_user_id=v_uid and m.tutor_user_id=v_tutor_user_id
      and m.created_at>=now()-interval '10 minutes'
      and m.status in ('PENDING_ADMIN','SENT_TO_TUTOR')
  ) then
    raise exception 'You have already sent a message to this tutor recently. Please wait before sending another.';
  end if;

  insert into public.gc_student_tutor_messages(
    student_user_id,student_profile_id,student_name,student_email,student_phone,
    student_profile_snapshot,tutor_profile_id,tutor_user_id,tutor_name,message
  ) values (
    v_uid,v_profile_id,v_student_name,v_student_email,v_student_phone,
    coalesce(v_student,'{}'::jsonb),p_tutor_profile_id,v_tutor_user_id,v_tutor_name,v_msg
  ) returning id into v_id;

  return jsonb_build_object('success',true,'message_id',v_id,'status','PENDING_ADMIN');
end;
$$;
revoke all on function public.gc_student_submit_tutor_message(uuid,text) from public,anon;
grant execute on function public.gc_student_submit_tutor_message(uuid,text) to authenticated;

create or replace function public.gc_admin_student_tutor_message_history()
returns table(
  message_id uuid, created_at timestamptz, student_user_id uuid, student_profile_id uuid,
  student_name text, student_email text, student_phone text, student_profile_snapshot jsonb,
  tutor_profile_id uuid, tutor_user_id uuid, tutor_name text, message text,
  message_status text, admin_note text, reviewed_at timestamptz, forwarded_at timestamptz
)
language plpgsql security definer
set search_path=public
as $$
begin
  if auth.uid() is null or not (
    exists(select 1 from public.profiles p where p.id=auth.uid() and lower(coalesce(p.role::text,'')) in ('admin','staff'))
    or lower(coalesce(auth.jwt()->'user_metadata'->>'role','')) in ('admin','staff')
    or lower(coalesce(auth.jwt()->'app_metadata'->>'role','')) in ('admin','staff')
    or lower(coalesce(auth.jwt()->>'email',''))='guruconnect.in@gmail.com'
    or lower(coalesce(auth.jwt()->'user_metadata'->>'is_staff',''))='true'
    or lower(coalesce(auth.jwt()->'app_metadata'->>'is_staff',''))='true'
  ) then raise exception 'Admin/Staff authorization required.'; end if;

  return query select m.id,m.created_at,m.student_user_id,m.student_profile_id,
    m.student_name,m.student_email,m.student_phone,m.student_profile_snapshot,
    m.tutor_profile_id,m.tutor_user_id,m.tutor_name,m.message,m.status,
    m.admin_note,m.reviewed_at,m.forwarded_at
  from public.gc_student_tutor_messages m order by m.created_at desc;
end;
$$;
revoke all on function public.gc_admin_student_tutor_message_history() from public,anon;
grant execute on function public.gc_admin_student_tutor_message_history() to authenticated;

create or replace function public.gc_admin_forward_student_tutor_message(p_message_id uuid)
returns jsonb
language plpgsql security definer
set search_path=public
as $$
declare m public.gc_student_tutor_messages%rowtype;
begin
  if auth.uid() is null or not (
    exists(select 1 from public.profiles p where p.id=auth.uid() and lower(coalesce(p.role::text,'')) in ('admin','staff'))
    or lower(coalesce(auth.jwt()->'user_metadata'->>'role','')) in ('admin','staff')
    or lower(coalesce(auth.jwt()->'app_metadata'->>'role','')) in ('admin','staff')
    or lower(coalesce(auth.jwt()->>'email',''))='guruconnect.in@gmail.com'
    or lower(coalesce(auth.jwt()->'user_metadata'->>'is_staff',''))='true'
    or lower(coalesce(auth.jwt()->'app_metadata'->>'is_staff',''))='true'
  ) then raise exception 'Admin/Staff authorization required.'; end if;

  select * into m from public.gc_student_tutor_messages where id=p_message_id for update;
  if not found then raise exception 'Student message not found.'; end if;
  if m.status<>'PENDING_ADMIN' then raise exception 'This message has already been reviewed.'; end if;
  if not exists(
    select 1 from public.tutor_profiles t join public.profiles p on p.id=t.user_id
    where t.id=m.tutor_profile_id and t.user_id=m.tutor_user_id
      and lower(coalesce(p.role::text,''))='tutor'
      and coalesce(t.is_hidden,false)=false and coalesce(t.is_disabled,false)=false
  ) then raise exception 'The selected tutor account is no longer available.'; end if;

  insert into public.gc_notifications(
    recipient_profile_id,recipient_role,sender_profile_id,type,title,body,request_id,connection_id
  ) values (
    m.tutor_user_id::text,'tutor',auth.uid()::text,
    'ADMIN_FORWARDED_TUTOR_MESSAGE','New Student Message (Admin Reviewed)',
    'Student: '||m.student_name||E'\n\nMessage: '||m.message,
    null,null
  );

  update public.gc_student_tutor_messages
    set status='SENT_TO_TUTOR',reviewed_by=auth.uid(),reviewed_at=now(),
        forwarded_at=now(),updated_at=now()
  where id=m.id;
  return jsonb_build_object('success',true,'message_id',m.id,'status','SENT_TO_TUTOR');
end;
$$;
revoke all on function public.gc_admin_forward_student_tutor_message(uuid) from public,anon;
grant execute on function public.gc_admin_forward_student_tutor_message(uuid) to authenticated;

create or replace function public.gc_admin_reject_student_tutor_message(
  p_message_id uuid,p_admin_note text default null
) returns jsonb
language plpgsql security definer
set search_path=public
as $$
begin
  if auth.uid() is null or not (
    exists(select 1 from public.profiles p where p.id=auth.uid() and lower(coalesce(p.role::text,'')) in ('admin','staff'))
    or lower(coalesce(auth.jwt()->'user_metadata'->>'role','')) in ('admin','staff')
    or lower(coalesce(auth.jwt()->'app_metadata'->>'role','')) in ('admin','staff')
    or lower(coalesce(auth.jwt()->>'email',''))='guruconnect.in@gmail.com'
    or lower(coalesce(auth.jwt()->'user_metadata'->>'is_staff',''))='true'
    or lower(coalesce(auth.jwt()->'app_metadata'->>'is_staff',''))='true'
  ) then raise exception 'Admin/Staff authorization required.'; end if;

  update public.gc_student_tutor_messages
    set status='REJECTED',admin_note=nullif(trim(coalesce(p_admin_note,'')),''),
        reviewed_by=auth.uid(),reviewed_at=now(),updated_at=now()
  where id=p_message_id and status='PENDING_ADMIN';
  if not found then raise exception 'Pending student message not found.'; end if;
  return jsonb_build_object('success',true,'message_id',p_message_id,'status','REJECTED');
end;
$$;
revoke all on function public.gc_admin_reject_student_tutor_message(uuid,text) from public,anon;
grant execute on function public.gc_admin_reject_student_tutor_message(uuid,text) to authenticated;

notify pgrst,'reload schema';
commit;
