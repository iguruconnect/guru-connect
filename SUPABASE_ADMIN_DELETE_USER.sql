-- GURU CONNECT — Secure Admin Delete User (Student/Tutor)
-- Run once in Supabase SQL Editor.
-- The dashboard calls this RPC instead of an Edge Function.

create or replace function public.gc_admin_delete_user(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  caller uuid := auth.uid();
  caller_email text;
  target_role text;
begin
  if caller is null then
    raise exception 'Staff/Admin authentication is required.';
  end if;

  select lower(email) into caller_email from auth.users where id = caller;

  if caller_email <> 'guruconnect.in@gmail.com'
     and not exists (
       select 1 from public.profiles
       where id = caller and lower(coalesce(role,'')) = 'admin'
     ) then
    raise exception 'Only an authorized Admin can delete users.';
  end if;

  if p_user_id is null then
    raise exception 'User ID is required.';
  end if;

  select lower(role) into target_role from public.profiles where id = p_user_id;
  if target_role is null then
    raise exception 'User profile was not found.';
  end if;

  if target_role not in ('student','tutor') then
    raise exception 'Only Student/Tutor accounts can be deleted from this dashboard.';
  end if;

  delete from public.tutor_profiles where user_id = p_user_id;
  delete from public.student_profiles where user_id = p_user_id;
  delete from public.profiles where id = p_user_id;
  delete from auth.users where id = p_user_id;

  return jsonb_build_object('ok', true, 'user_id', p_user_id, 'role', target_role);
end;
$$;

revoke all on function public.gc_admin_delete_user(uuid) from public;
grant execute on function public.gc_admin_delete_user(uuid) to authenticated;
notify pgrst, 'reload schema';
