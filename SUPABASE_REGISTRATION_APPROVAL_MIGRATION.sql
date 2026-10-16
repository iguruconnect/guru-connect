-- GURU CONNECT registration approval workflow
-- Safe additive migration: existing Student/Tutor records remain approved; new registration code sets explicit pending/limited status.
begin;

alter table public.profiles
  add column if not exists registration_approval_status text not null default 'APPROVED',
  add column if not exists registration_approved boolean not null default true,
  add column if not exists registration_approval_note text,
  add column if not exists registration_approved_at timestamptz;

alter table public.student_profiles
  add column if not exists registration_approval_status text not null default 'APPROVED',
  add column if not exists registration_approved boolean not null default true,
  add column if not exists registration_approval_note text,
  add column if not exists registration_approved_at timestamptz;

alter table public.tutor_profiles
  add column if not exists registration_approval_status text not null default 'APPROVED',
  add column if not exists registration_approved boolean not null default true,
  add column if not exists registration_approval_note text,
  add column if not exists registration_approved_at timestamptz;

comment on column public.profiles.registration_approval_status is 'APPROVED, PENDING_ADMIN_APPROVAL, REGISTERED_LIMITED, or REJECTED.';
comment on column public.profiles.registration_approved is 'Whether Admin approved full member access. Email OTP verification is separate.';
comment on column public.student_profiles.registration_approval_status is 'Student registration/full-feature approval state.';
comment on column public.tutor_profiles.registration_approval_status is 'Tutor registration approval state; tutor registrations require Admin approval.';

create or replace function public.gc_admin_set_registration_approval(
  p_user_id uuid,
  p_approved boolean,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_role text;
  v_status text;
begin
  if not public.gc_is_staff_admin() then
    raise exception 'Staff/Admin authorization required';
  end if;
  if p_user_id is null then raise exception 'User ID is required'; end if;

  select lower(role) into v_role from public.profiles where id=p_user_id;
  if v_role not in ('student','tutor') then
    raise exception 'Student/Tutor profile not found for this user';
  end if;

  v_status := case when coalesce(p_approved,false) then 'APPROVED' else 'REJECTED' end;

  update public.profiles
     set registration_approval_status=v_status,
         registration_approved=coalesce(p_approved,false),
         registration_approval_note=nullif(trim(coalesce(p_note,'')),''),
         registration_approved_at=case when coalesce(p_approved,false) then now() else null end,
         updated_at=now()
   where id=p_user_id;

  if v_role='student' then
    update public.student_profiles
       set registration_approval_status=v_status,
           registration_approved=coalesce(p_approved,false),
           registration_approval_note=nullif(trim(coalesce(p_note,'')),''),
           registration_approved_at=case when coalesce(p_approved,false) then now() else null end
     where user_id=p_user_id;
  else
    update public.tutor_profiles
       set registration_approval_status=v_status,
           registration_approved=coalesce(p_approved,false),
           registration_approval_note=nullif(trim(coalesce(p_note,'')),''),
           registration_approved_at=case when coalesce(p_approved,false) then now() else null end,
           verified=coalesce(p_approved,false),
           registration_status=case when coalesce(p_approved,false) then 'approved' else 'rejected' end
     where user_id=p_user_id;
  end if;

  return jsonb_build_object('ok',true,'user_id',p_user_id,'role',v_role,'registration_approval_status',v_status);
end;
$$;

revoke all on function public.gc_admin_set_registration_approval(uuid,boolean,text) from public;
grant execute on function public.gc_admin_set_registration_approval(uuid,boolean,text) to authenticated;

notify pgrst, 'reload schema';
commit;
