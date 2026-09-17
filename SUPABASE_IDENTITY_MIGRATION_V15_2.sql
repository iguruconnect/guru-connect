-- GURU CONNECT — V15.2 IDENTITY MIGRATION / SELF-HEALING MEMBER LINK
-- Run this ONCE in Supabase SQL Editor.
-- Purpose: link existing Student/Tutor rows to the real Supabase Auth user_id.
-- It also installs the gc_get_my_member_profile() RPC used after login.
-- Safe to run more than once.

-- 1) Make sure every Auth member has a canonical public.profiles row when
--    enough registration metadata exists.
insert into public.profiles (id, role, full_name, email, phone)
select
  u.id,
  case
    when exists (
      select 1 from public.gc_registration_submissions g
      where g.auth_user_id = u.id and lower(coalesce(g.role,'')) = 'tutor'
    ) then 'tutor'
    when exists (
      select 1 from public.gc_registration_submissions g
      where g.auth_user_id = u.id and lower(coalesce(g.role,'')) = 'student'
    ) then 'student'
    when lower(coalesce(u.raw_user_meta_data->>'role','')) in ('student','tutor')
      then lower(u.raw_user_meta_data->>'role')
    else null
  end,
  coalesce(nullif(u.raw_user_meta_data->>'name',''), split_part(coalesce(u.email,''),'@',1)),
  lower(u.email),
  nullif(u.raw_user_meta_data->>'phone','')
from auth.users u
where
  lower(coalesce(u.raw_user_meta_data->>'role','')) in ('student','tutor')
  or exists (
    select 1 from public.gc_registration_submissions g
    where g.auth_user_id = u.id
      and lower(coalesce(g.role,'')) in ('student','tutor')
  )
on conflict (id) do update
set
  role = coalesce(nullif(excluded.role,''), public.profiles.role),
  full_name = coalesce(nullif(excluded.full_name,''), public.profiles.full_name),
  email = coalesce(excluded.email, public.profiles.email),
  phone = coalesce(excluded.phone, public.profiles.phone);

-- 2) Student profiles already have an email column. Link unlinked rows by the
--    verified Auth email, but only where the match is unique.
with candidates as (
  select
    s.id as profile_id,
    u.id as auth_id,
    row_number() over (partition by s.id order by u.created_at desc) as rn
  from public.student_profiles s
  join auth.users u
    on lower(trim(coalesce(s.email,''))) = lower(trim(coalesce(u.email,'')))
  where nullif(trim(coalesce(s.email,'')),'') is not null
)
update public.student_profiles s
set user_id = c.auth_id
from candidates c
where s.id = c.profile_id
  and c.rn = 1
  and (s.user_id is null or s.user_id <> c.auth_id);

-- 3) Tutor profiles do not contain an email column in this project.
--    Link them using the canonical profiles row (same Auth UUID) and, for
--    legacy rows, the registration audit row's stored form-data name.
update public.tutor_profiles t
set user_id = p.id
from public.profiles p
where t.user_id is null
  and lower(coalesce(p.role,'')) = 'tutor'
  and nullif(trim(coalesce(p.full_name,'')),'') is not null
  and lower(trim(coalesce(t.name,''))) = lower(trim(p.full_name));

update public.tutor_profiles t
set user_id = g.auth_user_id
from public.gc_registration_submissions g
where t.user_id is null
  and lower(coalesce(g.role,'')) = 'tutor'
  and g.auth_user_id is not null
  and lower(trim(coalesce(t.name,''))) = lower(trim(coalesce(g.form_data->>'name','')))
  and (
    select count(*)
    from public.tutor_profiles t2
    where t2.user_id is null
      and lower(trim(coalesce(t2.name,''))) = lower(trim(coalesce(g.form_data->>'name','')))
  ) = 1;

-- 4) Install the runtime identity RPC. It first uses user_id, then performs a
--    controlled legacy-email/name recovery and writes the recovered user_id.
create or replace function public.gc_get_my_member_profile()
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  uid uuid := auth.uid();
  em text := lower(trim(coalesce(auth.jwt()->>'email','')));
  st public.student_profiles;
  tr public.tutor_profiles;
  pr public.profiles;
  candidate_id uuid;
  candidate_count integer;
  reg_name text;
  reg_role text;
begin
  if uid is null then
    raise exception 'Authenticated Supabase session is required';
  end if;

  -- Direct links are authoritative.
  select * into st from public.student_profiles where user_id = uid limit 1;
  if found then
    return jsonb_build_object('role','student','profile',to_jsonb(st));
  end if;

  select * into tr from public.tutor_profiles where user_id = uid limit 1;
  if found then
    return jsonb_build_object('role','tutor','profile',to_jsonb(tr));
  end if;

  -- Student legacy recovery by email.
  if em <> '' then
    select count(*), min(s.id) into candidate_count, candidate_id
    from public.student_profiles s
    where lower(trim(coalesce(s.email,''))) = em;

    if candidate_count = 1 then
      update public.student_profiles
      set user_id = uid
      where id = candidate_id;
      select * into st from public.student_profiles where id = candidate_id;
      return jsonb_build_object('role','student','profile',to_jsonb(st));
    end if;
  end if;

  -- Tutor legacy recovery. Tutor email is not stored in tutor_profiles, so use
  -- the registration audit record or canonical profiles name.
  select lower(coalesce(g.role,'')), nullif(trim(coalesce(g.form_data->>'name','')), '')
    into reg_role, reg_name
  from public.gc_registration_submissions g
  where g.auth_user_id = uid
  order by g.created_at desc nulls last
  limit 1;

  if reg_name is not null and lower(coalesce(reg_role,'')) = 'tutor' then
    select count(*), min(t.id) into candidate_count, candidate_id
    from public.tutor_profiles t
    where t.user_id is null
      and lower(trim(coalesce(t.name,''))) = lower(trim(reg_name));
    if candidate_count = 1 then
      update public.tutor_profiles set user_id = uid where id = candidate_id;
      select * into tr from public.tutor_profiles where id = candidate_id;
      return jsonb_build_object('role','tutor','profile',to_jsonb(tr));
    end if;
  end if;

  select * into pr from public.profiles where id = uid limit 1;
  if found and lower(coalesce(pr.role,'')) in ('student','tutor') then
    if lower(pr.role) = 'student' then
      select * into st from public.student_profiles where user_id = uid limit 1;
      if found then return jsonb_build_object('role','student','profile',to_jsonb(st)); end if;
    else
      select * into tr from public.tutor_profiles where user_id = uid limit 1;
      if found then return jsonb_build_object('role','tutor','profile',to_jsonb(tr)); end if;
    end if;
  end if;

  return jsonb_build_object('role',null,'profile',null);
end;
$$;

revoke all on function public.gc_get_my_member_profile() from public;
grant execute on function public.gc_get_my_member_profile() to authenticated;

select pg_notify('pgrst', 'reload schema');
