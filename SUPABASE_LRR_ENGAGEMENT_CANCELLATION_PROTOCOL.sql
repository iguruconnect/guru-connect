-- GURU CONNECT LRR Engagement / Cancellation Protocol
-- Review this migration before running it in the Supabase SQL Editor.
-- Does not alter wallets or perform any coin transfer/refund.

begin;

alter table public.gc_learning_requests_v2
  add column if not exists gc_lectures_started boolean not null default false,
  add column if not exists gc_lectures_started_at timestamptz,
  add column if not exists gc_cancellation_status text not null default 'NONE',
  add column if not exists gc_cancellation_requested_by uuid,
  add column if not exists gc_cancellation_requested_role text,
  add column if not exists gc_cancellation_reason text,
  add column if not exists gc_cancellation_requested_at timestamptz,
  add column if not exists gc_cancellation_admin_note text;

create index if not exists gc_lrr_cancellation_status_idx
  on public.gc_learning_requests_v2 (gc_cancellation_status);

create or replace function public.gc_mark_lrr_lecture_started(p_request_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member record;
  v_lrr record;
begin
  if auth.uid() is null then raise exception 'Please sign in again.'; end if;

  select id, role into v_member
  from public.profiles
  where user_id = auth.uid()
    and lower(coalesce(role,'')) = 'tutor'
  limit 1;

  if v_member.id is null then raise exception 'Only the assigned Tutor can record the first lecture.'; end if;

  select * into v_lrr
  from public.gc_learning_requests_v2
  where id::text = p_request_id
  for update;

  if v_lrr.id is null then raise exception 'Learning Request not found.'; end if;
  if coalesce(v_lrr.tutor_id::text,'') <> v_member.id::text then
    raise exception 'Only the assigned Tutor can record the first lecture.';
  end if;
  if upper(coalesce(v_lrr.status,'')) not in ('ACCEPTED','TUTOR_ACCEPTED') then
    raise exception 'Lecture start can only be recorded for an accepted, active engagement.';
  end if;
  if coalesce(v_lrr.gc_cancellation_status,'NONE') <> 'NONE' then
    raise exception 'This LRR already has a cancellation under Admin review.';
  end if;

  update public.gc_learning_requests_v2
  set gc_lectures_started = true,
      gc_lectures_started_at = coalesce(gc_lectures_started_at, now())
  where id::text = p_request_id;

  return jsonb_build_object('ok',true,'lecture_started',true,'request_id',p_request_id);
end;
$$;

create or replace function public.gc_request_lrr_cancellation(p_request_id text, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member record;
  v_lrr record;
  v_role text;
begin
  if auth.uid() is null then raise exception 'Please sign in again.'; end if;
  if length(trim(coalesce(p_reason,''))) < 3 then raise exception 'Please provide a cancellation reason.'; end if;

  select id, role into v_member
  from public.profiles
  where user_id = auth.uid()
    and lower(coalesce(role,'')) in ('student','tutor')
  limit 1;

  if v_member.id is null then raise exception 'A registered Student or Tutor profile is required.'; end if;
  v_role := lower(v_member.role);

  select * into v_lrr
  from public.gc_learning_requests_v2
  where id::text = p_request_id
  for update;

  if v_lrr.id is null then raise exception 'Learning Request not found.'; end if;
  if v_role = 'student' and coalesce(v_lrr.student_id::text,'') <> v_member.id::text then
    raise exception 'You can only cancel your own Learning Request engagement.';
  end if;
  if v_role = 'tutor' and coalesce(v_lrr.tutor_id::text,'') <> v_member.id::text then
    raise exception 'Only the assigned Tutor can request cancellation.';
  end if;
  if upper(coalesce(v_lrr.status,'')) not in ('ACCEPTED','TUTOR_ACCEPTED','IN_PROGRESS','TUTOR_COMPLETED','PENDING_ADMIN_APPROVAL','PENDING_ADMIN_REVIEW') then
    raise exception 'Only an accepted engagement can be cancelled through this process.';
  end if;
  if coalesce(v_lrr.gc_cancellation_status,'NONE') = 'PENDING_ADMIN_REVIEW' then
    raise exception 'This engagement is already awaiting Admin review.';
  end if;
  if upper(coalesce(v_lrr.status,'')) in ('COMPLETED','APPROVED','COMPLETED_SATISFIED','COMPLETED_NOT_SATISFIED') then
    raise exception 'This LRR is already completed or settled. Please contact Admin for a case review.';
  end if;
  if v_role = 'student' and coalesce(v_lrr.gc_lectures_started,false) then
    raise exception 'Student cancellation is not available after the first lecture. Please contact Admin if there is an exceptional circumstance.';
  end if;

  update public.gc_learning_requests_v2
  set gc_cancellation_status = 'PENDING_ADMIN_REVIEW',
      gc_cancellation_requested_by = auth.uid(),
      gc_cancellation_requested_role = v_role,
      gc_cancellation_reason = left(trim(p_reason),1000),
      gc_cancellation_requested_at = now(),
      status = 'PENDING_ADMIN_REVIEW'
  where id::text = p_request_id;

  return jsonb_build_object(
    'ok',true,
    'request_id',p_request_id,
    'cancellation_status','PENDING_ADMIN_REVIEW',
    'coins_settled',false,
    'message','LRR is awaiting Admin review; no coins were transferred.'
  );
end;
$$;

revoke all on function public.gc_mark_lrr_lecture_started(text) from public;
revoke all on function public.gc_request_lrr_cancellation(text,text) from public;
grant execute on function public.gc_mark_lrr_lecture_started(text) to authenticated;
grant execute on function public.gc_request_lrr_cancellation(text,text) to authenticated;

commit;
