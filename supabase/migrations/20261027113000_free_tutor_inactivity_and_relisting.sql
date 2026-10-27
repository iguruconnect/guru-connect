-- GURU CONNECT: Free tutor inactivity freeze, revenue-share audit and relisting requests.
-- Independent of GURU Coins, wallets, ledger, LRR, connections and escrow.
begin;

alter table public.tutor_profiles
  add column if not exists last_tuition_received_at timestamptz,
  add column if not exists free_profile_frozen_at timestamptz,
  add column if not exists free_profile_freeze_reason text,
  add column if not exists relisting_requested_at timestamptz,
  add column if not exists relisting_status text not null default 'NONE';

alter table public.tutor_profiles
  drop constraint if exists tutor_profiles_relisting_status_check;
alter table public.tutor_profiles
  add constraint tutor_profiles_relisting_status_check
  check (relisting_status in ('NONE','REQUESTED','APPROVED','REJECTED'));

create table if not exists public.gc_tutor_tuition_revenue (
  id uuid primary key default gen_random_uuid(),
  tutor_user_id uuid not null references public.profiles(id) on delete restrict,
  student_name text,
  tuition_start_date date not null,
  monthly_tuition_fee numeric(12,2) not null check (monthly_tuition_fee >= 0),
  commission_percent numeric(5,2) not null check (commission_percent in (0,5)),
  commission_amount numeric(12,2) not null check (commission_amount >= 0),
  revenue_share_status text not null default 'PENDING'
    check (revenue_share_status in ('PENDING','PAID','WAIVED','DISPUTED')),
  revenue_share_paid_at timestamptz,
  payment_mode text,
  transaction_number text,
  cash_received_by text,
  cash_receiver_id text,
  admin_note text,
  recorded_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint gc_tutor_tuition_revenue_commission_amount_check
    check (commission_amount = round(monthly_tuition_fee * commission_percent / 100, 2))
);
create index if not exists gc_tutor_tuition_revenue_user_date_idx
  on public.gc_tutor_tuition_revenue(tutor_user_id, tuition_start_date desc);

create table if not exists public.gc_tutor_relisting_requests (
  id uuid primary key default gen_random_uuid(),
  tutor_user_id uuid not null references public.profiles(id) on delete restrict,
  reason text not null check (length(trim(reason)) >= 10),
  status text not null default 'REQUESTED'
    check (status in ('REQUESTED','APPROVED','REJECTED')),
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  admin_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists gc_tutor_relisting_requests_status_idx
  on public.gc_tutor_relisting_requests(status, created_at desc);
create index if not exists gc_tutor_relisting_requests_user_idx
  on public.gc_tutor_relisting_requests(tutor_user_id, created_at desc);

alter table public.gc_tutor_tuition_revenue enable row level security;
alter table public.gc_tutor_relisting_requests enable row level security;

drop policy if exists gc_tutor_tuition_revenue_admin_only on public.gc_tutor_tuition_revenue;
create policy gc_tutor_tuition_revenue_admin_only
on public.gc_tutor_tuition_revenue for all to authenticated
using (public.is_admin() or exists (
  select 1 from public.profiles p where p.id=auth.uid()
  and lower(coalesce(p.role,'')) in ('admin','staff')
))
with check (public.is_admin() or exists (
  select 1 from public.profiles p where p.id=auth.uid()
  and lower(coalesce(p.role,'')) in ('admin','staff')
));

drop policy if exists gc_tutor_relisting_select_own_or_admin on public.gc_tutor_relisting_requests;
create policy gc_tutor_relisting_select_own_or_admin
on public.gc_tutor_relisting_requests for select to authenticated
using (tutor_user_id=auth.uid() or public.is_admin() or exists (
  select 1 from public.profiles p where p.id=auth.uid()
  and lower(coalesce(p.role,'')) in ('admin','staff')
));

drop policy if exists gc_tutor_relisting_insert_own on public.gc_tutor_relisting_requests;
create policy gc_tutor_relisting_insert_own
on public.gc_tutor_relisting_requests for insert to authenticated
with check (tutor_user_id=auth.uid() and status='REQUESTED');

drop policy if exists gc_tutor_relisting_admin_update on public.gc_tutor_relisting_requests;
create policy gc_tutor_relisting_admin_update
on public.gc_tutor_relisting_requests for update to authenticated
using (public.is_admin() or exists (
  select 1 from public.profiles p where p.id=auth.uid()
  and lower(coalesce(p.role,'')) in ('admin','staff')
))
with check (public.is_admin() or exists (
  select 1 from public.profiles p where p.id=auth.uid()
  and lower(coalesce(p.role,'')) in ('admin','staff')
));

-- A Free tutor is inactive after 90 days from the last recorded tuition, or
-- from profile creation if no tuition has ever been recorded.
create or replace function public.gc_admin_freeze_inactive_free_tutors()
returns integer
language plpgsql
security definer
set search_path=public
as $$
declare affected integer;
begin
  -- Scheduled pg_cron/service-role calls have no end-user auth.uid().
  -- Browser callers have execute permission only when authenticated and must be Admin.
  if auth.uid() is not null and not (public.is_admin() or exists (
    select 1 from public.profiles p where p.id=auth.uid()
    and lower(coalesce(p.role,'')) in ('admin','staff')
  )) then
    raise exception 'Admin access required';
  end if;

  update public.tutor_profiles t
     set is_hidden=true,
         is_disabled=true,
         free_profile_frozen_at=now(),
         free_profile_freeze_reason='No tuition recorded for 90 days',
         updated_at=now()
   where lower(coalesce(t.membership_type,'free')) <> 'premium'
     and coalesce(t.membership_status,'') not in ('PREMIUM_ACTIVE')
     and coalesce(t.is_hidden,false)=false
     and coalesce(t.is_disabled,false)=false
     and coalesce(t.last_tuition_received_at, t.created_at) is not null
     and coalesce(t.last_tuition_received_at, t.created_at) <= now() - interval '90 days';
  get diagnostics affected = row_count;
  return affected;
end;
$$;

-- Only the authenticated tutor can request a relisting; review and unfreeze are
-- handled by the Admin dashboard after reviewing the revenue-share history.
create or replace function public.gc_tutor_request_relisting(p_reason text)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'Login required'; end if;
  if length(trim(coalesce(p_reason,''))) < 10 then
    raise exception 'Please enter at least 10 characters explaining your relisting request';
  end if;
  if not exists (select 1 from public.tutor_profiles t where t.user_id=auth.uid()) then
    raise exception 'Tutor profile not found';
  end if;
  if exists (select 1 from public.gc_tutor_relisting_requests r
             where r.tutor_user_id=auth.uid() and r.status='REQUESTED') then
    raise exception 'You already have a relisting request pending Admin review';
  end if;
  insert into public.gc_tutor_relisting_requests(tutor_user_id,reason)
  values(auth.uid(),trim(p_reason)) returning id into v_id;
  update public.tutor_profiles
     set relisting_requested_at=now(), relisting_status='REQUESTED'
   where user_id=auth.uid();
  return v_id;
end;
$$;


-- Run the freeze check daily when pg_cron is installed on this Supabase project.
-- If pg_cron is not enabled, the Admin dashboard can invoke the protected RPC
-- after deployment until scheduling is enabled by the project owner.
do $schedule$
begin
  if exists (select 1 from pg_extension where extname='pg_cron') then
    if not exists (select 1 from cron.job where jobname='gc-free-tutor-inactivity-freeze-daily') then
      perform cron.schedule(
        'gc-free-tutor-inactivity-freeze-daily',
        '17 2 * * *',
        $job$select public.gc_admin_freeze_inactive_free_tutors();$job$
      );
    end if;
  end if;
exception when undefined_table or undefined_function then
  raise notice 'pg_cron is not configured; schedule gc_admin_freeze_inactive_free_tutors() daily in Supabase.';
end
$schedule$;

revoke all on function public.gc_admin_freeze_inactive_free_tutors() from public, anon;
grant execute on function public.gc_admin_freeze_inactive_free_tutors() to authenticated;
revoke all on function public.gc_tutor_request_relisting(text) from public, anon;
grant execute on function public.gc_tutor_request_relisting(text) to authenticated;

comment on table public.gc_tutor_tuition_revenue is 'Admin-only tuition and 5% Free-tutor revenue-share audit trail; no GURU Coin transactions.';
comment on table public.gc_tutor_relisting_requests is 'Private Free-tutor requests for Admin review before profile visibility is restored.';
commit;
