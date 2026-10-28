-- GURU CONNECT: Public Tutor Search Inquiries
-- Run once in Supabase SQL Editor. This creates a separate inquiry workflow;
-- it does not alter tutor profiles, Learning Requests, wallets, or coin ledgers.

create table if not exists public.gc_tutor_inquiries (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  visitor_name text not null,
  visitor_phone text not null,
  visitor_email text not null,
  tutor_id uuid not null,
  tutor_name text not null,
  search_class text,
  course text,
  subjects text,
  status text not null default 'NEW' check (status in ('NEW','FORWARDED','CLOSED')),
  forwarded_to text,
  admin_note text,
  forwarded_at timestamptz
);

create index if not exists gc_tutor_inquiries_created_at_idx
  on public.gc_tutor_inquiries (created_at desc);
create index if not exists gc_tutor_inquiries_status_idx
  on public.gc_tutor_inquiries (status);

alter table public.gc_tutor_inquiries enable row level security;
revoke all on public.gc_tutor_inquiries from anon, authenticated;

create or replace function public.gc_submit_tutor_inquiry(
  p_visitor_name text,
  p_visitor_phone text,
  p_visitor_email text,
  p_tutor_id uuid,
  p_tutor_name text,
  p_search_class text default null,
  p_course text default null,
  p_subjects text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if nullif(trim(p_visitor_name), '') is null
     or nullif(trim(p_visitor_phone), '') is null
     or nullif(trim(p_visitor_email), '') is null then
    raise exception 'Name, phone number and email are required.';
  end if;
  if length(trim(p_visitor_name)) > 120
     or length(trim(p_visitor_phone)) > 20
     or length(trim(p_visitor_email)) > 254 then
    raise exception 'Please check the length of your contact details.';
  end if;
  if trim(p_visitor_email) !~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$' then
    raise exception 'Please enter a valid email address.';
  end if;
  if p_tutor_id is null or nullif(trim(p_tutor_name), '') is null then
    raise exception 'A tutor must be selected for the inquiry.';
  end if;
  if not exists (
    select 1 from public.tutor_profiles t
    where t.id = p_tutor_id
      and coalesce(t.is_hidden, false) = false
      and coalesce(t.is_disabled, false) = false
      and lower(coalesce(t.registration_status::text, '')) = 'approved'
  ) then
    -- Some older approved profiles use the explicit approval flag.
    if not exists (
      select 1 from public.tutor_profiles t
      where t.id = p_tutor_id
        and coalesce(t.is_hidden, false) = false
        and coalesce(t.is_disabled, false) = false
        and (coalesce(t.registration_approved, false) = true
             or lower(coalesce(t.registration_approval_status::text, '')) = 'approved')
    ) then
      raise exception 'This tutor is not currently available for inquiry.';
    end if;
  end if;

  insert into public.gc_tutor_inquiries
    (visitor_name, visitor_phone, visitor_email, tutor_id, tutor_name, search_class, course, subjects)
  values
    (trim(p_visitor_name), trim(p_visitor_phone), trim(p_visitor_email),
     p_tutor_id, trim(p_tutor_name), nullif(trim(p_search_class), ''),
     nullif(trim(p_course), ''), nullif(trim(p_subjects), ''))
  returning id into v_id;

  return jsonb_build_object('success', true, 'inquiry_id', v_id);
end;
$$;

revoke all on function public.gc_submit_tutor_inquiry(text,text,text,uuid,text,text,text,text) from public;
grant execute on function public.gc_submit_tutor_inquiry(text,text,text,uuid,text,text,text,text) to anon, authenticated;

create or replace function public.gc_admin_list_tutor_inquiries()
returns setof public.gc_tutor_inquiries
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and lower(coalesce(p.role::text, '')) in ('admin','staff')
    )
    or lower(coalesce(auth.jwt()->'user_metadata'->>'role','')) in ('admin','staff')
    or lower(coalesce(auth.jwt()->'app_metadata'->>'role','')) in ('admin','staff')
    or lower(coalesce(auth.jwt()->>'email','')) = 'guruconnect.in@gmail.com'
    or lower(coalesce(auth.jwt()->'user_metadata'->>'is_staff','')) = 'true'
    or lower(coalesce(auth.jwt()->'app_metadata'->>'is_staff','')) = 'true'
  ) then
    raise exception 'Admin/Staff authorization required.';
  end if;
  return query select * from public.gc_tutor_inquiries order by created_at desc;
end;
$$;

create or replace function public.gc_admin_mark_tutor_inquiry_forwarded(
  p_inquiry_id uuid,
  p_forwarded_to text,
  p_admin_note text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and lower(coalesce(p.role, '')) in ('admin','staff')
    )
    or lower(coalesce(auth.jwt()->'user_metadata'->>'role','')) in ('admin','staff')
    or lower(coalesce(auth.jwt()->'app_metadata'->>'role','')) in ('admin','staff')
    or lower(coalesce(auth.jwt()->'user_metadata'->>'is_staff','')) = 'true'
    or lower(coalesce(auth.jwt()->'app_metadata'->>'is_staff','')) = 'true'
  ) then
    raise exception 'Admin/Staff authorization required.';
  end if;
  if nullif(trim(p_forwarded_to), '') is null then
    raise exception 'Enter the Premium Tutor(s) or recipient details before marking forwarded.';
  end if;
  update public.gc_tutor_inquiries
     set status = 'FORWARDED',
         forwarded_to = trim(p_forwarded_to),
         admin_note = nullif(trim(p_admin_note), ''),
         forwarded_at = now()
   where id = p_inquiry_id;
  if not found then raise exception 'Inquiry not found.'; end if;
  return jsonb_build_object('success', true);
end;
$$;

revoke all on function public.gc_admin_list_tutor_inquiries() from public, anon;
revoke all on function public.gc_admin_mark_tutor_inquiry_forwarded(uuid,text,text) from public, anon;
grant execute on function public.gc_admin_list_tutor_inquiries() to authenticated;
grant execute on function public.gc_admin_mark_tutor_inquiry_forwarded(uuid,text,text) to authenticated;

notify pgrst, 'reload schema';
