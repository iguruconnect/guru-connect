-- GURU CONNECT — REGISTRATION PROFILE SAVE FIX
-- Run this ONCE in the Supabase SQL Editor.
-- Fixes registration failures caused by ON CONFLICT / missing user_id UNIQUE constraints
-- and avoids relying on PostgREST's client-side conflict target for registration.
-- It also works when an older profile row already exists.

begin;

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
  v_profile public.profiles;
  v_student public.student_profiles;
  v_tutor public.tutor_profiles;
begin
  if auth.uid() is null then
    raise exception 'Authenticated Supabase session is required';
  end if;

  if auth.uid() <> p_user_id then
    raise exception 'Registration user mismatch';
  end if;

  if v_role not in ('student','tutor') then
    raise exception 'Registration role must be student or tutor';
  end if;

  -- Canonical member profile: UPDATE first, INSERT if it does not exist.
  -- This deliberately avoids ON CONFLICT so registration does not depend on
  -- a particular PostgREST conflict target or schema-cache state.
  update public.profiles
     set role = v_role,
         full_name = nullif(trim(coalesce(p_data->>'name','')),''),
         email = lower(trim(coalesce(p_data->>'email',''))),
         phone = nullif(trim(coalesce(p_data->>'phone','')),''),
         photo_url = null
   where id = p_user_id;

  get diagnostics v_count = row_count;

  if v_count = 0 then
    insert into public.profiles (id, role, full_name, email, phone, photo_url)
    values (
      p_user_id,
      v_role,
      nullif(trim(coalesce(p_data->>'name','')),''),
      lower(trim(coalesce(p_data->>'email',''))),
      nullif(trim(coalesce(p_data->>'phone','')),''),
      null
    );
  end if;

  if v_role = 'student' then
    -- Existing row is updated by user_id; otherwise a new row is inserted.
    update public.student_profiles
       set name = p_data->>'name',
           course = p_data->>'course',
           stream = p_data->>'stream',
           standard = p_data->>'std',
           subject = p_data->>'subject',
           learning_requirement = p_data->>'learning_requirement',
           year = p_data->>'std',
           semester = '',
           college = p_data->>'college',
           division = p_data->>'division',
           roll_number = p_data->>'roll',
           email = lower(trim(coalesce(p_data->>'email',''))),
           phone = p_data->>'phone',
           location = p_data->>'location',
           address = '',
           mode = '',
           teaching_mode = '',
           languages = '',
           availability = '',
           member_since = p_data->>'registration_date',
           record_no = '',
           data_source = 'registration',
           about_me = p_data->>'about_me',
           achievement_photos = '[]'::jsonb,
           helpline_plan = '',
           helpline_status = '',
           helpline_course = '',
           helpline_subject = '',
           helpline_subject_count = 0,
           helpline_amount = 0,
           privacy = '{}'::jsonb
     where user_id = p_user_id;

    get diagnostics v_count = row_count;

    if v_count = 0 then
      insert into public.student_profiles (
        user_id,name,course,stream,standard,subject,learning_requirement,year,semester,
        college,division,roll_number,email,phone,location,address,mode,teaching_mode,
        languages,availability,member_since,record_no,data_source,about_me,achievement_photos,
        helpline_plan,helpline_status,helpline_course,helpline_subject,helpline_subject_count,
        helpline_amount,privacy,photo_url
      ) values (
        p_user_id,p_data->>'name',p_data->>'course',p_data->>'stream',p_data->>'std',
        p_data->>'subject',p_data->>'learning_requirement',p_data->>'std','',
        p_data->>'college',p_data->>'division',p_data->>'roll',
        lower(trim(coalesce(p_data->>'email',''))),p_data->>'phone',p_data->>'location','',
        '','','','',p_data->>'registration_date','registration',p_data->>'about_me','[]'::jsonb,
        '','','','',0,0,'{}'::jsonb,null
      );
    end if;

    select * into v_student from public.student_profiles where user_id = p_user_id limit 1;
    return jsonb_build_object('ok',true,'role','student','profile',to_jsonb(v_student));

  else
    update public.tutor_profiles
       set name = p_data->>'name',
           subject = p_data->>'subject',
           stream = '',
           experience = p_data->>'experience',
           qualification = p_data->>'qualification',
           college = p_data->>'tutor_college',
           teaching_college = p_data->>'teaching_college',
           address = p_data->>'address',
           price = p_data->>'rate_hour',
           about_me = p_data->>'about_me',
           photo_url = null,
           verified = false,
           paid_status = 'PENDING',
           rating = null,
           review_count = 0,
           students_taught = '',
           teaching_mode = '',
           location = p_data->>'location',
           languages = '',
           availability = '',
           teaching_since = p_data->>'registration_date',
           is_illustrative = false,
           registration_status = 'registered'
     where user_id = p_user_id;

    get diagnostics v_count = row_count;

    if v_count = 0 then
      insert into public.tutor_profiles (
        user_id,name,subject,stream,experience,qualification,college,teaching_college,address,
        price,about_me,photo_url,verified,paid_status,rating,review_count,students_taught,
        teaching_mode,location,languages,availability,teaching_since,is_illustrative,registration_status
      ) values (
        p_user_id,p_data->>'name',p_data->>'subject','',p_data->>'experience',p_data->>'qualification',
        p_data->>'tutor_college',p_data->>'teaching_college',p_data->>'address',p_data->>'rate_hour',
        p_data->>'about_me',null,false,'PENDING',null,0,'','','',p_data->>'location','',
        '',p_data->>'registration_date',false,'registered'
      );
    end if;

    select * into v_tutor from public.tutor_profiles where user_id = p_user_id limit 1;
    return jsonb_build_object('ok',true,'role','tutor','profile',to_jsonb(v_tutor));
  end if;
end;
$$;

revoke all on function public.gc_register_verified_profile(uuid,text,jsonb) from public;
grant execute on function public.gc_register_verified_profile(uuid,text,jsonb) to authenticated;

notify pgrst, 'reload schema';
commit;
