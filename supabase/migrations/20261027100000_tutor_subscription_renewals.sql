-- GURU CONNECT tutor subscription renewals and auditable subscription history.
-- No wallet, coin, LRR, connection, or escrow tables are changed.
begin;
alter table public.tutor_profiles
  add column if not exists tuition_commission_percent numeric(5,2) not null default 5;
update public.tutor_profiles set tuition_commission_percent=case when lower(coalesce(membership_type,'free'))='premium' then 0 else 5 end
where tuition_commission_percent is null or tuition_commission_percent not in (0,5);
create table if not exists public.gc_tutor_subscription_renewals (
 id uuid primary key default gen_random_uuid(),
 tutor_user_id uuid not null references public.profiles(id) on delete cascade,
 premium_months integer not null check (premium_months between 1 and 24),
 verified_months integer not null default 0 check (verified_months between 0 and 24),
 amount numeric(10,2) not null check (amount >= 0),
 payment_link text,
 status text not null default 'REQUESTED' check (status in ('REQUESTED','PAYMENT_SUBMITTED','APPROVED','REJECTED')),
 payment_mode text,
 transaction_number text,
 cash_receiver_name text,
 cash_receiver_id text,
 voucher_number text,
 voucher_issuer_name text,
 voucher_issuer_id text,
 voucher_contact text,
 voucher_rbn text,
 valid_from timestamptz,
 valid_until timestamptz,
 submitted_at timestamptz,
 approved_at timestamptz,
 admin_note text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 constraint gc_tutor_renewal_verified_requires_premium check (verified_months <= premium_months)
);
create index if not exists gc_tutor_subscription_renewals_user_created_idx on public.gc_tutor_subscription_renewals(tutor_user_id,created_at desc);
alter table public.gc_tutor_subscription_renewals enable row level security;
drop policy if exists gc_tutor_renewal_select_own_or_admin on public.gc_tutor_subscription_renewals;
create policy gc_tutor_renewal_select_own_or_admin on public.gc_tutor_subscription_renewals for select to authenticated using (
 tutor_user_id=auth.uid() or public.is_admin() or exists(select 1 from public.profiles p where p.id=auth.uid() and lower(coalesce(p.role,'')) in ('admin','staff'))
);
drop policy if exists gc_tutor_renewal_insert_own_or_admin on public.gc_tutor_subscription_renewals;
create policy gc_tutor_renewal_insert_own_or_admin on public.gc_tutor_subscription_renewals for insert to authenticated with check (
 (tutor_user_id=auth.uid() and status='REQUESTED') or public.is_admin() or exists(select 1 from public.profiles p where p.id=auth.uid() and lower(coalesce(p.role,'')) in ('admin','staff'))
);
drop policy if exists gc_tutor_renewal_update_own_payment_or_admin on public.gc_tutor_subscription_renewals;
create policy gc_tutor_renewal_update_own_payment_or_admin on public.gc_tutor_subscription_renewals for update to authenticated using (
 (tutor_user_id=auth.uid() and status='REQUESTED') or public.is_admin() or exists(select 1 from public.profiles p where p.id=auth.uid() and lower(coalesce(p.role,'')) in ('admin','staff'))
) with check (
 (tutor_user_id=auth.uid() and status='PAYMENT_SUBMITTED') or public.is_admin() or exists(select 1 from public.profiles p where p.id=auth.uid() and lower(coalesce(p.role,'')) in ('admin','staff'))
);
comment on table public.gc_tutor_subscription_renewals is 'Auditable tutor subscription renewal requests and payment/validity history; independent of GURU Coins.';
commit;
