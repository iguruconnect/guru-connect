-- GURU CONNECT — Admin Delete User (Student/Tutor)
-- Run once in Supabase SQL Editor.
-- This creates a protected RPC used by the Staff/Admin dashboard.

create or replace function public.gc_admin_delete_user(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  caller uuid := auth.uid();
  target_role text;
begin
  if caller is null then
    raise exception 'Staff/Admin authentication is required.';
  end if;

  if caller::text <> '1df7606a-3a96-4116-b022-804b37a3c3dd'
     and not exists (
       select 1 from public.profiles
       where id = caller and lower(coalesce(role,'')) = 'admin'
     ) then
    raise exception 'Only an authorized Admin can delete users.';
  end if;

  if p_user_id is null then
    raise exception 'User ID is required.';
  end if;

  select role into target_role from public.profiles where id = p_user_id;
  if target_role is null then
    raise exception 'User profile was not found.';
  end if;

  if lower(target_role) not in ('student','tutor') then
    raise exception 'Only Student/Tutor accounts can be deleted from this dashboard.';
  end if;

  -- Delete the Auth user. Existing FK cascades remove linked profile rows where configured.
  -- Explicit profile cleanup is attempted first for projects without cascade rules.
  delete from public.tutor_profiles where user_id = p_user_id;
  delete from public.student_profiles where user_id = p_user_id;
  delete from public.profiles where id = p_user_id;
  delete from auth.users where id = p_user_id;

  return jsonb_build_object('ok', true, 'user_id', p_user_id, 'role', target_role);
end;
$$;

revoke all on function public.gc_admin_delete_user(uuid) from public;
grant execute on function public.gc_admin_delete_user(uuid) to authenticated;
