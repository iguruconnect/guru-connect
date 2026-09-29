-- GURU CONNECT: ADMIN CONTROL + REGISTRATION/PASSWORD REPAIR
-- Run this ONE file in Supabase SQL Editor.
-- This migration does NOT read, deduct, award, or modify GURU COINS.

begin;

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Common Staff/Admin authorization
-- ---------------------------------------------------------------------------
create or replace function public.gc_is_staff_admin()
returns boolean
language sql stable security definer
set search_path = public, auth
as $$
  select auth.uid() = '1df7606a-3a96-4116-b022-804b37a3c3dd'::uuid
     and lower(coalesce(auth.jwt() ->> 'email','')) = 'guruconnect.in@gmail.com';
$$;
revoke all on function public.gc_is_staff_admin() from public;
grant execute on function public.gc_is_staff_admin() to authenticated;

-- ---------------------------------------------------------------------------
-- Registration repair: never depends on ON CONFLICT(user_id).
-- Called only after the user's email has been verified by Supabase Auth.
-- ---------------------------------------------------------------------------
create or replace function public.gc_complete_registration(
  p_role text,
  p_data jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  uid uuid := auth.uid();
  r text := lower(trim(coalesce(p_role,'')));
  email_now text := lower(trim(coalesce(auth.jwt()->>'email','')));
  existing_id bigint;
begin
  if uid is null then raise exception 'Authentication session is required.'; end if;
  if r not in ('student','tutor') then raise exception 'Role must be Student or Tutor.'; end if;

  if not exists (
    select 1 from auth.users u
    where u.id=uid and u.email_confirmed_at is not null
  ) then
    raise exception 'Please verify your email before completing registration.';
  end if;

  if email_now = '' then raise exception 'Verified email is missing from the Auth session.'; end if;

  -- Canonical member row: id is the primary key, so no user_id conflict is involved.
  insert into public.profiles (id, role, full_name, email, phone, photo_url)
  values (
    uid, r,
    nullif(trim(coalesce(p_data->>'name','')), ''),
    email_now,
    nullif(trim(coalesce(p_data->>'phone','')), ''),
    null
  )
  on conflict (id) do update set
    role=excluded.role,
    full_name=coalesce(excluded.full_name, public.profiles.full_name),
    email=excluded.email,
    phone=coalesce(excluded.phone, public.profiles.phone);

  if r='student' then
    -- Update an existing row for this Auth user; otherwise insert a new row.
    update public.student_profiles set
      name=coalesce(nullif(p_data->>'name',''),name),
      course=coalesce(nullif(p_data->>'course',''),course),
      stream=coalesce(nullif(p_data->>'stream',''),stream),
      standard=coalesce(nullif(p_data->>'standard',''),standard),
      subject=coalesce(nullif(p_data->>'subject',''),subject),
      learning_requirement=coalesce(p_data->>'learning_requirement',learning_requirement),
      year=coalesce(nullif(p_data->>'year',''),year),
      semester=coalesce(nullif(p_data->>'semester',''),semester),
      college=coalesce(nullif(p_data->>'college',''),college),
      division=coalesce(nullif(p_data->>'division',''),division),
      roll_number=coalesce(nullif(p_data->>'roll_number',''),roll_number),
      email=email_now,
      phone=coalesce(nullif(p_data->>'phone',''),phone),
      location=coalesce(nullif(p_data->>'location',''),location),
      member_since=coalesce(nullif(p_data->>'member_since',''),member_since),
      data_source=coalesce(nullif(p_data->>'data_source',''),'registration'),
      about_me=coalesce(p_data->>'about_me',about_me),
      photo_url=null
    where user_id=uid;

    if not found then
      insert into public.student_profiles
      (user_id,name,course,stream,standard,subject,learning_requirement,year,semester,
       college,division,roll_number,email,phone,location,address,mode,teaching_mode,
       languages,availability,member_since,record_no,data_source,about_me,
       achievement_photos,helpline_plan,helpline_status,helpline_course,
       helpline_subject,helpline_subject_count,helpline_amount,privacy,photo_url)
      values
      (uid,p_data->>'name',p_data->>'course',p_data->>'stream',p_data->>'standard',
       p_data->>'subject',p_data->>'learning_requirement',p_data->>'year','',
       p_data->>'college',p_data->>'division',p_data->>'roll_number',email_now,
       p_data->>'phone',p_data->>'location','','','','',p_data->>'member_since',
       '', 'registration',p_data->>'about_me','[]'::jsonb,'','','', '',0,0,'{}'::jsonb,null);
    end if;

  else
    update public.tutor_profiles set
      name=coalesce(nullif(p_data->>'name',''),name),
      subject=coalesce(nullif(p_data->>'subject',''),subject),
      experience=coalesce(nullif(p_data->>'experience',''),experience),
      qualification=coalesce(nullif(p_data->>'qualification',''),qualification),
      college=coalesce(nullif(p_data->>'tutor_college',''),college),
      teaching_college=coalesce(nullif(p_data->>'teaching_college',''),teaching_college),
      address=coalesce(nullif(p_data->>'address',''),address),
      price=coalesce(nullif(p_data->>'rate_hour',''),price),
      about_me=coalesce(p_data->>'about_me',about_me),
      location=coalesce(nullif(p_data->>'location',''),location),
      teaching_since=coalesce(nullif(p_data->>'registration_date',''),teaching_since),
      registration_status='registered'
    where user_id=uid;

    if not found then
      insert into public.tutor_profiles
      (user_id,name,subject,stream,experience,qualification,college,teaching_college,
       address,price,about_me,photo_url,verified,paid_status,rating,review_count,
       students_taught,teaching_mode,location,languages,availability,teaching_since,
       is_illustrative,registration_status)
      values
      (uid,p_data->>'name',p_data->>'subject','',p_data->>'experience',
       p_data->>'qualification',p_data->>'tutor_college',p_data->>'teaching_college',
       p_data->>'address',p_data->>'rate_hour',p_data->>'about_me',null,false,'PENDING',
       null,0,'','','','','',p_data->>'registration_date',false,'registered');
    end if;
  end if;

  -- Keep the Auth email canonical; this is intentionally not a password change.
  update auth.users set
    raw_user_meta_data = coalesce(raw_user_meta_data,'{}'::jsonb) ||
      jsonb_build_object('role',r,'name',p_data->>'name','phone',p_data->>'phone'),
    updated_at=now()
  where id=uid;

  return jsonb_build_object('ok',true,'user_id',uid,'role',r);
end;
$$;
revoke all on function public.gc_complete_registration(text,jsonb) from public;
grant execute on function public.gc_complete_registration(text,jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- Admin: search users
-- ---------------------------------------------------------------------------
create or replace function public.gc_admin_find_users(p_term text default '')
returns jsonb
language plpgsql security definer
set search_path=public,auth
as $$
declare q text := lower(trim(coalesce(p_term,''))); out jsonb;
begin
  if not public.gc_is_staff_admin() then raise exception 'Staff Admin authorization required.'; end if;

  select coalesce(jsonb_agg(x order by x->>'name'), '[]'::jsonb) into out
  from (
    select jsonb_build_object(
      'user_id',u.id,
      'role',p.role,
      'name',coalesce(p.full_name,u.raw_user_meta_data->>'name','User'),
      'email',coalesce(u.email,p.email),
      'phone',p.phone,
      'email_confirmed',u.email_confirmed_at is not null,
      'registration_status',
        case when p.role='tutor' then coalesce(t.registration_status,'registered')
             when p.role='student' then 'registered' else null end,
      'profile',
        case when p.role='tutor' then to_jsonb(t)
             when p.role='student' then to_jsonb(s) else null end
    ) x
    from auth.users u
    join public.profiles p on p.id=u.id
    left join public.tutor_profiles t on t.user_id=u.id
    left join public.student_profiles s on s.user_id=u.id
    where lower(coalesce(p.role,'')) in ('student','tutor')
      and (
        q='' or lower(coalesce(u.email,'')) like '%'||q||'%'
        or lower(coalesce(p.full_name,'')) like '%'||q||'%'
        or lower(coalesce(p.phone,'')) like '%'||q||'%'
      )
  ) q1;
  return out;
end;
$$;
revoke all on function public.gc_admin_find_users(text) from public;
grant execute on function public.gc_admin_find_users(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Admin: edit Student/Tutor profile + contact information
-- ---------------------------------------------------------------------------
create or replace function public.gc_admin_edit_user(p_user_id uuid,p_data jsonb)
returns jsonb
language plpgsql security definer
set search_path=public,auth
as $$
declare rr text;
begin
  if not public.gc_is_staff_admin() then raise exception 'Staff Admin authorization required.'; end if;
  select lower(role) into rr from public.profiles where id=p_user_id;
  if rr not in ('student','tutor') then raise exception 'Only Student/Tutor accounts can be edited.'; end if;

  update public.profiles set
    full_name=coalesce(nullif(p_data->>'name',''),full_name),
    email=coalesce(nullif(lower(trim(p_data->>'email')),''),email),
    phone=coalesce(nullif(p_data->>'phone',''),phone)
  where id=p_user_id;

  if rr='tutor' then
    update public.tutor_profiles set
      name=coalesce(nullif(p_data->>'name',''),name),
      subject=coalesce(nullif(p_data->>'subject',''),subject),
      stream=coalesce(nullif(p_data->>'stream',''),stream),
      qualification=coalesce(nullif(p_data->>'qualification',''),qualification),
      location=coalesce(nullif(p_data->>'location',''),location)
    where user_id=p_user_id;

    update auth.users set
      email=coalesce(nullif(lower(trim(p_data->>'email')),''),email),
      raw_user_meta_data=coalesce(raw_user_meta_data,'{}'::jsonb) ||
        jsonb_build_object('name',coalesce(p_data->>'name',raw_user_meta_data->>'name'),
                           'phone',coalesce(p_data->>'phone',raw_user_meta_data->>'phone')),
      updated_at=now()
    where id=p_user_id;
  else
    update public.student_profiles set
      name=coalesce(nullif(p_data->>'name',''),name),
      course=coalesce(nullif(p_data->>'course',''),course),
      stream=coalesce(nullif(p_data->>'stream',''),stream),
      subject=coalesce(nullif(p_data->>'subject',''),subject),
      location=coalesce(nullif(p_data->>'location',''),location)
    where user_id=p_user_id;

    update auth.users set
      email=coalesce(nullif(lower(trim(p_data->>'email')),''),email),
      raw_user_meta_data=coalesce(raw_user_meta_data,'{}'::jsonb) ||
        jsonb_build_object('name',coalesce(p_data->>'name',raw_user_meta_data->>'name'),
                           'phone',coalesce(p_data->>'phone',raw_user_meta_data->>'phone')),
      updated_at=now()
    where id=p_user_id;
  end if;

  return jsonb_build_object('ok',true,'user_id',p_user_id);
end;
$$;
revoke all on function public.gc_admin_edit_user(uuid,jsonb) from public;
grant execute on function public.gc_admin_edit_user(uuid,jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- Admin: verified tick + payment status. GURU COINS are not touched.
-- ---------------------------------------------------------------------------
create or replace function public.gc_admin_set_tutor_flags(
  p_user_id uuid,
  p_verified boolean,
  p_paid boolean
)
returns jsonb
language plpgsql security definer
set search_path=public,auth
as $$
begin
  if not public.gc_is_staff_admin() then raise exception 'Staff Admin authorization required.'; end if;

  update public.tutor_profiles
  set verified=coalesce(p_verified,verified),
      paid_status=case when p_paid is null then paid_status
                       when p_paid then 'PAID' else 'PENDING' end
  where user_id=p_user_id;

  if not found then raise exception 'Tutor profile not found.'; end if;
  return jsonb_build_object('ok',true,'user_id',p_user_id,'verified',p_verified,'paid',p_paid);
end;
$$;
revoke all on function public.gc_admin_set_tutor_flags(uuid,boolean,boolean) from public;
grant execute on function public.gc_admin_set_tutor_flags(uuid,boolean,boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- Admin: registration status
-- ---------------------------------------------------------------------------
create or replace function public.gc_admin_set_status(p_user_id uuid,p_status text)
returns jsonb
language plpgsql security definer
set search_path=public,auth
as $$
begin
  if not public.gc_is_staff_admin() then raise exception 'Staff Admin authorization required.'; end if;
  if lower(coalesce(p_status,'')) not in ('registered','pending_email','suspended') then
    raise exception 'Invalid status.';
  end if;
  update public.tutor_profiles set registration_status=lower(p_status)
    where user_id=p_user_id;
  if not found then
    -- Student profiles in this project do not require a separate status column.
    return jsonb_build_object('ok',true,'user_id',p_user_id,'status',lower(p_status));
  end if;
  return jsonb_build_object('ok',true,'user_id',p_user_id,'status',lower(p_status));
end;
$$;
revoke all on function public.gc_admin_set_status(uuid,text) from public;
grant execute on function public.gc_admin_set_status(uuid,text) to authenticated;

-- ---------------------------------------------------------------------------
-- Admin: password reset without exposing the service-role key.
-- ---------------------------------------------------------------------------
create or replace function public.gc_admin_reset_password(p_user_id uuid,p_password text)
returns jsonb
language plpgsql security definer
set search_path=public,auth
as $$
begin
  if not public.gc_is_staff_admin() then raise exception 'Staff Admin authorization required.'; end if;
  if length(coalesce(p_password,'')) < 8 then raise exception 'Password must be at least 8 characters.'; end if;
  if not exists (select 1 from public.profiles where id=p_user_id and lower(role) in ('student','tutor')) then
    raise exception 'Only Student/Tutor accounts can be reset.';
  end if;
  update auth.users
  set encrypted_password=crypt(p_password,gen_salt('bf')),
      updated_at=now()
  where id=p_user_id;
  if not found then raise exception 'Auth user not found.'; end if;
  return jsonb_build_object('ok',true,'user_id',p_user_id);
end;
$$;
revoke all on function public.gc_admin_reset_password(uuid,text) from public;
grant execute on function public.gc_admin_reset_password(uuid,text) to authenticated;

-- ---------------------------------------------------------------------------
-- Admin: delete Student/Tutor account and common linked rows.
-- This does not touch GURU Coins tables by name or logic.
-- ---------------------------------------------------------------------------
create or replace function public.gc_admin_delete_user(p_user_id uuid)
returns jsonb
language plpgsql security definer
set search_path=public,auth
as $$
declare rr text; r record;
begin
  if not public.gc_is_staff_admin() then raise exception 'Staff Admin authorization required.'; end if;
  select lower(role) into rr from public.profiles where id=p_user_id;
  if rr not in ('student','tutor') then raise exception 'Only Student/Tutor accounts can be deleted.'; end if;

  -- Remove rows from public tables that directly reference auth.users with
  -- a simple FK. The user's account is then removed from Auth.
  for r in
    select n.nspname as schema_name, c.relname as table_name, a.attname as column_name
    from pg_constraint fk
    join pg_class c on c.oid=fk.conrelid
    join pg_namespace n on n.oid=c.relnamespace
    join pg_attribute a on a.attrelid=c.oid and a.attnum=fk.conkey[1]
    where fk.contype='f'
      and fk.confrelid='auth.users'::regclass
      and array_length(fk.conkey,1)=1
      and n.nspname='public'
      and c.relname not in ('profiles','tutor_profiles','student_profiles')
  loop
    begin
      execute format('delete from %I.%I where %I=$1',r.schema_name,r.table_name,r.column_name) using p_user_id;
    exception when others then
      -- A protected/complex table is left for its own FK policy rather than
      -- making unrelated deletion fail.
      null;
    end;
  end loop;

  delete from public.tutor_profiles where user_id=p_user_id;
  delete from public.student_profiles where user_id=p_user_id;
  delete from public.profiles where id=p_user_id;
  delete from auth.users where id=p_user_id;

  if not found then raise exception 'Auth user could not be deleted.'; end if;
  return jsonb_build_object('ok',true,'user_id',p_user_id,'role',rr);
end;
$$;
revoke all on function public.gc_admin_delete_user(uuid) from public;
grant execute on function public.gc_admin_delete_user(uuid) to authenticated;

notify pgrst,'reload schema';
commit;
