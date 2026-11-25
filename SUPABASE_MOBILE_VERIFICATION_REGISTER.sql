-- GURU CONNECT: Mandatory mobile verification for NEW Student/Tutor registrations only.
-- Existing members are preserved as mobile-verified by the defaults below.
begin;

alter table public.profiles
  add column if not exists mobile_verified boolean not null default true,
  add column if not exists mobile_verification_status text not null default 'VERIFIED',
  add column if not exists mobile_verified_at timestamptz,
  add column if not exists mobile_verified_by uuid;

alter table public.student_profiles
  add column if not exists mobile_verified boolean not null default true,
  add column if not exists mobile_verification_status text not null default 'VERIFIED',
  add column if not exists mobile_verified_at timestamptz,
  add column if not exists mobile_verified_by uuid;

alter table public.tutor_profiles
  add column if not exists mobile_verified boolean not null default true,
  add column if not exists mobile_verification_status text not null default 'VERIFIED',
  add column if not exists mobile_verified_at timestamptz,
  add column if not exists mobile_verified_by uuid;

comment on column public.profiles.mobile_verified is 'Manual mobile verification flag. Existing accounts default true; new registrations explicitly set false.';
comment on column public.profiles.mobile_verification_status is 'VERIFIED or PENDING_CALL for manual GURU CONNECT phone verification.';

create table if not exists public.gc_mobile_verification_register (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null,
  role text not null check (role in ('student','tutor')),
  applicant_name text,
  mobile_number text,
  call_date date not null,
  call_time time not null,
  verification_officer text not null,
  outcome text not null check (outcome in ('VERIFIED','NO_ANSWER','CALL_BACK','INVALID_NUMBER','OTHER')),
  remarks text,
  recorded_by uuid not null,
  recorded_at timestamptz not null default now()
);

create index if not exists gc_mobile_verification_register_user_idx
  on public.gc_mobile_verification_register(auth_user_id, recorded_at desc);
create index if not exists gc_mobile_verification_register_role_idx
  on public.gc_mobile_verification_register(role, recorded_at desc);

alter table public.gc_mobile_verification_register enable row level security;
revoke all on public.gc_mobile_verification_register from anon, authenticated;

notify pgrst, 'reload schema';
commit;