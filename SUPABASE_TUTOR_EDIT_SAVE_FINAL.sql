-- GURU CONNECT — definitive Staff/Admin Tutor Edit Save migration
-- Run this ONCE in Supabase SQL Editor.
-- This creates the RPC that the Admin Tutor Editor calls.
-- IMPORTANT: tutor_profiles does NOT contain email/phone in the deployed schema;
-- those contact fields live in public.profiles and auth.users.

begin;

create or replace function public.gc_is_staff_admin()
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select auth.uid() = '1df7606a-3a96-4116-b022-804b37a3c3dd'::uuid
     and lower(coalesce(auth.jwt() ->> 'email','')) = 'guruconnect.in@gmail.com';
$$;

revoke all on function public.gc_is_staff_admin() from public;
grant execute on function public.gc_is_staff_admin() to authenticated;

create or replace function public.gc_staff_save_tutor_profile(
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
    raise exception 'Staff Admin authorization required';
  end if;

  if p_user_id is null then
    raise exception 'Tutor user ID is required';
  end if;

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
    rating = case when p_data ? 'rating' and nullif(p_data->>'rating','') is not null then (p_data->>'rating')::numeric else rating end,
    review_count = case when p_data ? 'review_count' and nullif(p_data->>'review_count','') is not null then (p_data->>'review_count')::integer else review_count end,
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

  -- Keep the member contact record synchronized for Admin edits.
  update public.profiles
  set full_name = coalesce(p_data->>'name', full_name),
      email = coalesce(p_data->>'email', email),
      phone = coalesce(p_data->>'phone', phone),
      photo_url = coalesce(p_data->>'photo_url', photo_url)
  where id = p_user_id;

  -- Forgot-password/login uses auth.users.email, so keep it synchronized too.
  if nullif(lower(trim(coalesce(p_data->>'email',''))),'') is not null
     and lower(trim(p_data->>'email')) <> lower(coalesce((select email from auth.users where id=p_user_id),'')) then
    update auth.users
       set email = lower(trim(p_data->>'email')),
           email_change = null,
           email_change_token_new = null,
           email_change_confirm_status = null,
           updated_at = now()
     where id = p_user_id;
  end if;

  return to_jsonb(r);
end;
$$;

revoke all on function public.gc_staff_save_tutor_profile(uuid, jsonb) from public;
grant execute on function public.gc_staff_save_tutor_profile(uuid, jsonb) to authenticated;

-- Refresh PostgREST's schema cache so the RPC is immediately visible to the website.
notify pgrst, 'reload schema';

commit;
