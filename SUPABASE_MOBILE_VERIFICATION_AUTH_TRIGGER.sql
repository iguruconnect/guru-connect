-- New auth-created Student/Tutor profiles start pending.
-- Existing profiles are untouched because the ON CONFLICT branch does not reset approval/mobile flags.
create or replace function public.gc_sync_auth_member()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $function$
declare
  m jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  r text := lower(coalesce(m->>'role', ''));
  nm text := coalesce(nullif(trim(m->>'name'), ''), split_part(coalesce(new.email, ''), '@', 1));
  ph text := nullif(trim(m->>'phone'), '');
  loc text := nullif(trim(m->>'location'), '');
  v_email_verified boolean := new.email_confirmed_at is not null;
  st text := case when v_email_verified then 'registered' else 'pending_email' end;
begin
  if r not in ('student','tutor') then return new; end if;

  insert into public.profiles
    (id,role,full_name,email,phone,registration_status,
     registration_approval_status,registration_approved,mobile_verified,mobile_verification_status)
  values
    (new.id,r,nm,lower(new.email),ph,st,
     'PENDING_ADMIN_APPROVAL',false,false,'PENDING_CALL')
  on conflict (id) do update set
    role=excluded.role,
    full_name=coalesce(excluded.full_name,public.profiles.full_name),
    email=excluded.email,
    phone=coalesce(excluded.phone,public.profiles.phone),
    registration_status=case when new.email_confirmed_at is not null then 'registered' else public.profiles.registration_status end;

  if r='student' then
    if not exists(select 1 from public.student_profiles where user_id=new.id) then
      insert into public.student_profiles
        (user_id,name,course,stream,standard,subject,learning_requirement,year,semester,
         college,division,roll_number,cgpa,email,phone,location,address,mode,teaching_mode,
         languages,availability,member_since,record_no,data_source,about_me,photo_url,
         registration_status,registration_approval_status,registration_approved,mobile_verified,mobile_verification_status)
      values
        (new.id,nm,nullif(m->>'course',''),nullif(m->>'stream',''),nullif(m->>'course',''),
         nullif(m->>'subject',''),nullif(m->>'subject',''),nullif(m->>'course',''),
         null,null,null,null,null,lower(new.email),ph,loc,null,null,null,null,null,
         to_char(now(),'Mon YYYY'),null,'supabase-auth',null,null,st,
         'PENDING_ADMIN_APPROVAL',false,false,'PENDING_CALL');
    else
      update public.student_profiles set
        registration_status=case when v_email_verified then 'registered' else registration_status end,
        email=lower(new.email),phone=coalesce(ph,phone),location=coalesce(loc,location)
      where user_id=new.id;
    end if;
  elsif r='tutor' then
    if not exists(select 1 from public.tutor_profiles where user_id=new.id) then
      insert into public.tutor_profiles
        (user_id,name,subject,stream,experience,qualification,college,teaching_college,
         address,price,about_me,photo_url,verified,paid_status,rating,review_count,
         students_taught,teaching_mode,location,languages,availability,teaching_since,
         is_illustrative,registration_status,registration_approval_status,registration_approved,
         mobile_verified,mobile_verification_status)
      values
        (new.id,nm,nullif(m->>'subject',''),nullif(m->>'stream',''),nullif(m->>'experience',''),
         nullif(m->>'qualification',''),nullif(m->>'college',''),nullif(m->>'college',''),
         loc,nullif(m->>'price',''),nullif(m->>'about_me',''),null,false,'PENDING',null,0,
         '',nullif(m->>'teaching_mode',''),loc,null,null,to_char(now(),'Mon YYYY'),false,st,
         'PENDING_ADMIN_APPROVAL',false,false,'PENDING_CALL');
    else
      update public.tutor_profiles set
        registration_status=case when v_email_verified then 'registered' else registration_status end,
        name=coalesce(nullif(nm,''),name),location=coalesce(loc,location)
      where user_id=new.id;
    end if;
  end if;
  return new;
end;
$function$;