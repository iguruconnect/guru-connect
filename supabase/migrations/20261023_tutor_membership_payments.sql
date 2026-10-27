-- GURU CONNECT tutor membership / payment metadata migration
-- Safe to run more than once. Does not delete accounts, LRRs, connections, or coin history.
begin;

alter table public.tutor_profiles
  add column if not exists membership_type text not null default 'free',
  add column if not exists membership_months integer not null default 0,
  add column if not exists membership_payment_mode text,
  add column if not exists membership_payment_amount numeric(10,2) not null default 0,
  add column if not exists membership_payment_transaction_number text,
  add column if not exists membership_cash_receiver_name text,
  add column if not exists membership_cash_receiver_id text,
  add column if not exists membership_voucher_number text,
  add column if not exists membership_voucher_issuer_name text,
  add column if not exists membership_voucher_issuer_id text,
  add column if not exists membership_voucher_contact text,
  add column if not exists membership_voucher_rbn text,
  add column if not exists membership_status text not null default 'FREE_TRIAL',
  add column if not exists membership_started_at timestamptz,
  add column if not exists membership_expires_at timestamptz,
  add column if not exists membership_review_due_at timestamptz,
  add column if not exists verified_badge_enabled boolean not null default false,
  add column if not exists verified_badge_months integer not null default 0,
  add column if not exists verified_badge_started_at timestamptz,
  add column if not exists verified_badge_expires_at timestamptz,
  add column if not exists free_last_qualifying_activity_at timestamptz,
  add column if not exists profile_hidden boolean not null default false,
  add column if not exists profile_hidden_reason text;

alter table public.tutor_profiles
  drop constraint if exists tutor_profiles_membership_type_check;
alter table public.tutor_profiles
  add constraint tutor_profiles_membership_type_check
  check (membership_type in ('free','premium'));

alter table public.tutor_profiles
  drop constraint if exists tutor_profiles_membership_months_check;
alter table public.tutor_profiles
  add constraint tutor_profiles_membership_months_check
  check (membership_months between 0 and 24);

alter table public.tutor_profiles
  drop constraint if exists tutor_profiles_verified_badge_months_check;
alter table public.tutor_profiles
  add constraint tutor_profiles_verified_badge_months_check
  check (verified_badge_months between 0 and 24);

-- Backfill existing tutor rows as Free, with a two-month review date.
update public.tutor_profiles
set membership_type = case
      when upper(coalesce(paid_status,'')) in ('PAID','ACTIVE','APPROVED') then 'premium'
      else coalesce(membership_type,'free')
    end,
    membership_started_at = coalesce(membership_started_at, now()),
    membership_review_due_at = coalesce(membership_review_due_at, coalesce(membership_started_at, now()) + interval '60 days'),
    membership_status = case
      when upper(coalesce(paid_status,'')) in ('PAID','ACTIVE','APPROVED') then 'PREMIUM_ACTIVE'
      else coalesce(membership_status,'FREE_TRIAL')
    end
where membership_started_at is null
   or membership_review_due_at is null
   or membership_status is null;

commit;

-- NOTE:
-- The registration form records payment claims for Admin review; it does not verify
-- UPI payments automatically. Admin approval must set actual membership/badge expiry.
-- Free-profile inactivity must be enforced in the server-side public tutor directory
-- query/RPC (and scheduled review process) before it can reliably hide a profile.
