-- GURU CONNECT — FINAL AUTH / ADMIN / REGISTRATION / DELETE REPAIR
-- Date: 2026-09-29
-- Run this ONE file in Supabase SQL Editor.
-- It is designed for the current Guru Connect HTML build.
-- It does NOT put a service-role key in the website.

begin;

-- ============================================================
-- 1. Common Staff/Admin authorization
-- ============================================================
create or replace function public.gc_is_staff_admin()
returns boolean
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  uid uuid := auth.uid();
  em text := lower(trim(coalesce(auth.jwt()->>'email','')));
  r text;
begin
  if uid is null then return false; end if;

  if em = 'guruconnect.in@gmail.com' then
    return true;
  end if;

  select lower(coalesce(role,'')) into r
  from public.profiles where id = uid limit 1;

  return r in ('admin','staff','administrator');
end;
$$;

revoke all on function public.gc_is_staff_admin() from public;
grant execute on function public.gc_is_staff_admin() to authenticated;

-- ============================================================
-- 2. Safe Auth-email synchronization
--    Fixes user_email_partial_key errors caused by attempting
--    to assign an email already owned by another Auth account.
-- ============================================================
create or replace function public.gc_admin_update_auth_email(
  p_user_id uuid,
  p_email text
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  new_email text := lower(trim(coalesce(p_email,'')));
  current_email text;
  other_id uuid;
  other_is_staff boolean := false;
begin
  if not public.gc_is_staff_admin() then
    raise exception 'Staff/Admin authorization required';
  end if;

  if p_user_id is null then
    raise exception 'User ID is required';
  end if;

  if new_email = '' or new_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'A valid email address is required';
  end if;

  select lower(coalesce(email,'')) into current_email
  from auth.users where id = p_user_id;

  if current_email is null then
    raise exception 'Supabase Auth user was not found for this profile';
  end if;

  if current_email = new_email then
    update public.profiles
       set email = new_email, updated_at = now()
     where id = p_user_id;
    return jsonb_build_object('ok',true,'user_id',p_user_id,'email',new_email,'changed',false);
  end if;

  select id into other_id
  from auth.users
  where lower(email) = new_email
    and id <> p_user_id
  limit 1;

  if other_id is not null then
    -- A previous failed registration can leave an orphan Auth account.
    -- It is safe for Staff/Admin to clean it only when it has NO linked
    -- GURU CONNECT profile and is not a staff/admin account.
    select exists(
      select 1 from public.gc_staff_admins sa
      join auth.users au on lower(coalesce(sa.email,''))=lower(coalesce(au.email,''))
      where au.id=other_id and coalesce(sa.active,false)=true
    ) into other_is_staff;

    if not exists (select 1 from public.profiles where id=other_id)
       and not exists (select 1 from public.tutor_profiles where user_id=other_id)
       and not exists (select 1 from public.student_profiles where user_id=other_id)
       and not other_is_staff then
      delete from auth.users where id=other_id;
      other_id := null;
    else
      raise exception 'Email % is already used by another active GURU CONNECT Auth account. Choose a different email address.', new_email;
    end if;
  end if;

  -- public.profiles may also have a unique/partial email index.
  if exists (
    select 1 from public.profiles
    where lower(coalesce(email,'')) = new_email
      and id <> p_user_id
  ) then
    raise exception 'Email % is already used by another GURU CONNECT profile. Choose a different email address.', new_email;
  end if;

  update auth.users
     set email = new_email,
         email_change = null,
         email_change_token_new = null,
         email_change_confirm_status = null,
         updated_at = now()
   where id = p_user_id;

  if not found then
    raise exception 'Supabase Auth user could not be updated';
  end if;

  update public.profiles
     set email = new_email, updated_at = now()
   where id = p_user_id;

  return jsonb_build_object('ok',true,'user_id',p_user_id,'email',new_email,'changed',true);
end;
$$;

revoke all on function public.gc_admin_update_auth_email(uuid,text) from public;
grant execute on function public.gc_admin_update_auth_email(uuid,text) to authenticated;

-- ============================================================
-- 3. Full Tutor edit RPC
-- ============================================================
create or replace function public.gc_admin_update_tutor_profile(
  p_user_id uuid,
  p_data jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  r public.tutor_profiles;
  new_email text := nullif(lower(trim(coalesce(p_data->>'email',''))),'');
begin
  if not public.gc_is_staff_admin() then
    raise exception 'Staff/Admin authorization required';
  end if;

  if p_user_id is null then raise exception 'Tutor user ID is required'; end if;

  -- Email uniqueness and orphan-Auth cleanup are handled centrally by
  -- gc_admin_update_auth_email below, so the same rules apply everywhere.

  update public.tutor_profiles
  set
    name = coalesce(p_data->>'name', name),
    subject = coalesce(p_data->>'subject', subject),
    stream = coalesce(p_data->>'stream', stream),
    experience = coalesce(p_data->>'experience', experience),
    qualification = coalesce(p_data->>'qualification', qualification),
    college = coalesce(p_data->>'college', college),
    teaching_college = coalesce(p_data->>'teaching_college', teaching_college),
    address = coalesce(p_data->>'address', address),
    price = coalesce(p_data->>'price', price),
    about_me = coalesce(p_data->>'about_me', about_me),
    photo_url = coalesce(p_data->>'photo_url', photo_url),
    rating = case when p_data ? 'rating' and nullif(p_data->>'rating','') is not null
                  then (p_data->>'rating')::numeric else rating end,
    review_count = case when p_data ? 'review_count' and nullif(p_data->>'review_count','') is not null
                  then (p_data->>'review_count')::integer else review_count end,
    students_taught = coalesce(p_data->>'students_taught', students_taught),
    teaching_mode = coalesce(p_data->>'teaching_mode', teaching_mode),
    location = coalesce(p_data->>'location', location),
    languages = coalesce(p_data->>'languages', languages),
    availability = coalesce(p_data->>'availability', availability),
    teaching_since = coalesce(p_data->>'teaching_since', teaching_since),
    verified = case when p_data ? 'verified' then (p_data->>'verified')::boolean else verified end,
    paid_status = case when p_data ? 'paid_status' then p_data->>'paid_status' else paid_status end
  where user_id = p_user_id
  returning * into r;

  if not found then
    raise exception 'Registered Tutor profile not found for user ID %', p_user_id;
  end if;

  update public.profiles
  set full_name = coalesce(p_data->>'name', full_name),
      email = coalesce(new_email, email),
      phone = coalesce(p_data->>'phone', phone),
      photo_url = coalesce(p_data->>'photo_url', photo_url),
      updated_at = now()
  where id = p_user_id;

  if new_email is not null then
    perform public.gc_admin_update_auth_email(p_user_id,new_email);
  end if;

  return jsonb_build_object('ok',true,'profile',to_jsonb(r));
end;
$$;

revoke all on function public.gc_admin_update_tutor_profile(uuid,jsonb) from public;
grant execute on function public.gc_admin_update_tutor_profile(uuid,jsonb) to authenticated;

-- Compatibility RPC used by the later Tutor editor.
create or replace function public.gc_staff_save_tutor_profile(
  p_user_id uuid,
  p_data jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  return public.gc_admin_update_tutor_profile(p_user_id,p_data);
end;
$$;

revoke all on function public.gc_staff_save_tutor_profile(uuid,jsonb) from public;
grant execute on function public.gc_staff_save_tutor_profile(uuid,jsonb) to authenticated;

-- ============================================================
-- 4. Admin PAID / Verified Tick — NO COIN CHARGE
-- ============================================================
create or replace function public.gc_admin_set_tutor_approval(
  p_user_id uuid,
  p_data jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  r public.tutor_profiles;
begin
  if not public.gc_is_staff_admin() then
    raise exception 'Staff/Admin authorization required';
  end if;

  update public.tutor_profiles
  set
    paid_status = case
      when p_data ? 'paid_status' then upper(coalesce(p_data->>'paid_status','PENDING'))
      else paid_status
    end,
    verified = case
      when p_data ? 'verified' then (p_data->>'verified')::boolean
      else verified
    end
  where user_id = p_user_id
  returning * into r;

  if not found then
    raise exception 'Tutor profile not found for user ID %',p_user_id;
  end if;

  return jsonb_build_object(
    'ok',true,
    'user_id',p_user_id,
    'paid_status',r.paid_status,
    'verified',r.verified
  );
end;
$$;

revoke all on function public.gc_admin_set_tutor_approval(uuid,jsonb) from public;
grant execute on function public.gc_admin_set_tutor_approval(uuid,jsonb) to authenticated;

-- ============================================================
-- 5. Full Student edit RPC
-- ============================================================
create or replace function public.gc_admin_update_student_profile(
  p_user_id uuid,
  p_data jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  r public.student_profiles;
  new_email text := nullif(lower(trim(coalesce(p_data->>'email',''))),'');
begin
  if not public.gc_is_staff_admin() then
    raise exception 'Staff/Admin authorization required';
  end if;

  if p_user_id is null then raise exception 'Student user ID is required'; end if;

  if new_email is not null then
    if exists (select 1 from auth.users where lower(email)=new_email and id<>p_user_id) then
      raise exception 'Student email is already used by another Auth account.';
    end if;
    if exists (select 1 from public.profiles where lower(coalesce(email,''))=new_email and id<>p_user_id) then
      raise exception 'Student email is already used by another profile.';
    end if;
  end if;

  update public.student_profiles
  set
    name = coalesce(p_data->>'name',name),
    course = coalesce(p_data->>'course',course),
    stream = coalesce(p_data->>'stream',stream),
    standard = coalesce(p_data->>'standard',standard),
    subject = coalesce(p_data->>'subject',subject),
    learning_requirement = coalesce(p_data->>'learning_requirement',learning_requirement),
    college = coalesce(p_data->>'college',college),
    division = coalesce(p_data->>'division',division),
    roll_number = coalesce(p_data->>'roll',roll_number),
    phone = coalesce(p_data->>'phone',phone),
    email = coalesce(new_email,email),
    location = coalesce(p_data->>'location',location),
    address = coalesce(p_data->>'address',address),
    mode = coalesce(p_data->>'mode',mode),
    teaching_mode = coalesce(p_data->>'teaching_mode',teaching_mode),
    languages = coalesce(p_data->>'languages',languages),
    availability = coalesce(p_data->>'availability',availability),
    about_me = coalesce(p_data->>'about_me',about_me),
    photo_url = coalesce(p_data->>'photo_url',photo_url)
  where user_id=p_user_id
  returning * into r;

  if not found then raise exception 'Registered Student profile not found for user ID %',p_user_id; end if;

  update public.profiles
  set full_name=coalesce(p_data->>'name',full_name),
      email=coalesce(new_email,email),
      phone=coalesce(p_data->>'phone',phone),
      photo_url=coalesce(p_data->>'photo_url',photo_url),
      updated_at=now()
  where id=p_user_id;

  if new_email is not null then
    perform public.gc_admin_update_auth_email(p_user_id,new_email);
  end if;

  return jsonb_build_object('ok',true,'profile',to_jsonb(r));
end;
$$;

revoke all on function public.gc_admin_update_student_profile(uuid,jsonb) from public;
grant execute on function public.gc_admin_update_student_profile(uuid,jsonb) to authenticated;

-- ============================================================
-- 6. Permanent Admin Delete
--    Returns BOTH ok and deleted because older/newer frontends used
--    different response names.
-- ============================================================
create or replace function public.gc_admin_delete_user(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  target_role text;
  tutor_pid uuid;
  student_pid uuid;
  tbl text;
  col text;
  rel regclass;
begin
  if not public.gc_is_staff_admin() then
    raise exception 'Only an authorized Staff/Admin can delete users.';
  end if;
  if p_user_id is null then raise exception 'User ID is required'; end if;

  select lower(role) into target_role from public.profiles where id=p_user_id;
  if target_role is null then
    if exists(select 1 from auth.users where id=p_user_id) then
      raise exception 'Auth account exists but the Student/Tutor profile is missing. Delete was blocked for safety.';
    end if;
    raise exception 'User profile was not found.';
  end if;
  if target_role not in ('student','tutor') then
    raise exception 'Only Student/Tutor accounts can be deleted here.';
  end if;

  select id into tutor_pid from public.tutor_profiles where user_id=p_user_id limit 1;
  select id into student_pid from public.student_profiles where user_id=p_user_id limit 1;

  -- Remove known GURU CONNECT child records first.  The column checks make
  -- this migration tolerant of optional tables/columns in older deployments.
  foreach tbl in array ARRAY[
    'gc_learning_request_messages','gc_learning_request_connections',
    'gc_connection_requests','gc_learning_requests','gc_learning_requests_v2',
    'gc_coin_ledger','gc_coin_wallets'
  ] loop
    if to_regclass('public.'||tbl) is not null then
      foreach col in array ARRAY['user_id','profile_id','tutor_id','student_id','sender_id','receiver_id','created_by'] loop
        if exists (
          select 1 from information_schema.columns
          where table_schema='public' and table_name=tbl and column_name=col
        ) then
          if col='user_id' then
            execute format('delete from public.%I where %I=$1',tbl,col) using p_user_id;
          elsif col='profile_id' then
            execute format('delete from public.%I where %I=$1',tbl,col) using p_user_id;
            if tutor_pid is not null then execute format('delete from public.%I where %I=$1',tbl,col) using tutor_pid; end if;
            if student_pid is not null then execute format('delete from public.%I where %I=$1',tbl,col) using student_pid; end if;
          else
            execute format('delete from public.%I where %I=$1',tbl,col) using p_user_id;
            if tutor_pid is not null then execute format('delete from public.%I where %I=$1',tbl,col) using tutor_pid; end if;
            if student_pid is not null then execute format('delete from public.%I where %I=$1',tbl,col) using student_pid; end if;
          end if;
        end if;
      end loop;
    end if;
  end loop;

  delete from public.tutor_profiles where user_id=p_user_id;
  delete from public.student_profiles where user_id=p_user_id;
  delete from public.profiles where id=p_user_id;
  delete from auth.users where id=p_user_id;

  if not found then
    raise exception 'Supabase Auth account could not be deleted.';
  end if;

  return jsonb_build_object('ok',true,'deleted',true,'user_id',p_user_id,'role',target_role);
end;
$$;

revoke all on function public.gc_admin_delete_user(uuid) from public;
grant execute on function public.gc_admin_delete_user(uuid) to authenticated;

-- ============================================================
-- 7. Registration RPC — UPDATE FIRST, INSERT SECOND.
--    No ON CONFLICT(user_id), avoiding old schema constraints.
-- ============================================================
create or replace function public.gc_register_verified_profile(
  p_user_id uuid,
  p_role text,
  p_data jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_role text := lower(trim(coalesce(p_role,'')));
  v_count integer;
  v_student public.student_profiles;
  v_tutor public.tutor_profiles;
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Registration authentication mismatch. Please restart registration and verify the email again.';
  end if;

  if v_role not in ('student','tutor') then raise exception 'Role must be student or tutor'; end if;

  -- Prevent the public profile email from colliding with another member.
  if exists (
    select 1 from public.profiles
    where lower(coalesce(email,''))=lower(trim(coalesce(p_data->>'email','')))
      and id<>p_user_id
  ) then
    raise exception 'This email is already attached to another GURU CONNECT profile. Please use the existing account or another email.';
  end if;

  update public.profiles
  set role=v_role,
      full_name=nullif(trim(coalesce(p_data->>'name','')),''),
      email=lower(trim(coalesce(p_data->>'email',''))),
      phone=nullif(trim(coalesce(p_data->>'phone','')),''),
      updated_at=now()
  where id=p_user_id;

  get diagnostics v_count=row_count;

  if v_count=0 then
    insert into public.profiles(id,role,full_name,email,phone,photo_url)
    values(p_user_id,v_role,nullif(trim(coalesce(p_data->>'name','')),''),
           lower(trim(coalesce(p_data->>'email',''))),
           nullif(trim(coalesce(p_data->>'phone','')),''),null);
  end if;

  if v_role='student' then
    update public.student_profiles
    set name=p_data->>'name',
        course=p_data->>'course',
        stream=p_data->>'stream',
        standard=p_data->>'std',
        subject=p_data->>'subject',
        learning_requirement=p_data->>'learning_requirement',
        year=p_data->>'std',
        college=p_data->>'college',
        division=p_data->>'division',
        roll_number=p_data->>'roll',
        email=lower(trim(coalesce(p_data->>'email',''))),
        phone=p_data->>'phone',
        location=p_data->>'location',
        about_me=p_data->>'about_me',
        photo_url=nullif(trim(coalesce(p_data->>'photo_url','')),'')
    where user_id=p_user_id;

    get diagnostics v_count=row_count;
    if v_count=0 then
      insert into public.student_profiles(
        user_id,name,course,stream,standard,subject,learning_requirement,year,
        college,division,roll_number,email,phone,location,about_me,photo_url
      ) values(
        p_user_id,p_data->>'name',p_data->>'course',p_data->>'stream',p_data->>'std',
        p_data->>'subject',p_data->>'learning_requirement',p_data->>'std',
        p_data->>'college',p_data->>'division',p_data->>'roll',
        lower(trim(coalesce(p_data->>'email',''))),p_data->>'phone',
        p_data->>'location',p_data->>'about_me',
        nullif(trim(coalesce(p_data->>'photo_url','')),'')
      );
    end if;

    select * into v_student from public.student_profiles where user_id=p_user_id limit 1;
    return jsonb_build_object('ok',true,'role','student','profile',to_jsonb(v_student));
  end if;

  update public.tutor_profiles
  set name=p_data->>'name',
      subject=p_data->>'subject',
      experience=p_data->>'experience',
      qualification=p_data->>'qualification',
      college=p_data->>'tutor_college',
      teaching_college=p_data->>'teaching_college',
      address=p_data->>'address',
      price=p_data->>'rate_hour',
      about_me=p_data->>'about_me',
      photo_url=nullif(trim(coalesce(p_data->>'photo_url','')),''),
      verified=false,
      paid_status='PENDING',
      registration_status='registered',
      is_illustrative=false
  where user_id=p_user_id;

  get diagnostics v_count=row_count;
  if v_count=0 then
    insert into public.tutor_profiles(
      user_id,name,subject,stream,experience,qualification,college,teaching_college,
      address,price,about_me,photo_url,verified,paid_status,registration_status,is_illustrative
    ) values(
      p_user_id,p_data->>'name',p_data->>'subject','',p_data->>'experience',
      p_data->>'qualification',p_data->>'tutor_college',p_data->>'teaching_college',
      p_data->>'address',p_data->>'rate_hour',p_data->>'about_me',
      nullif(trim(coalesce(p_data->>'photo_url','')),''),false,'PENDING','registered',false
    );
  end if;

  select * into v_tutor from public.tutor_profiles where user_id=p_user_id limit 1;
  return jsonb_build_object('ok',true,'role','tutor','profile',to_jsonb(v_tutor));
end;
$$;

revoke all on function public.gc_register_verified_profile(uuid,text,jsonb) from public;
grant execute on function public.gc_register_verified_profile(uuid,text,jsonb) to authenticated;

notify pgrst,'reload schema';

commit;
