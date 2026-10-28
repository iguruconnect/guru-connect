-- GURU CONNECT: safe tutor membership foundation
-- Additive only. This migration does NOT modify profiles.id, tutor_profiles.public_id,
-- GURU Coin wallets/ledger, Learning Requests, connections, or existing payment rows.
-- Do not infer tuition income from GURU Coins or Learning Request escrow.

create table if not exists public.gc_tutor_membership_controls (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  plan_tier text not null default 'UNCLASSIFIED'
    check (plan_tier in ('UNCLASSIFIED', 'FREE', 'PREMIUM')),
  account_state text not null default 'ACTIVE'
    check (account_state in ('ACTIVE', 'FROZEN', 'RELIST_PENDING')),
  last_verified_tuition_at timestamptz,
  inactivity_started_at timestamptz,
  revenue_share_rate numeric(5,4) not null default 0.0500
    check (revenue_share_rate >= 0 and revenue_share_rate <= 1),
  relist_requested_at timestamptz,
  relist_request_note text,
  last_admin_decision text
    check (last_admin_decision is null or last_admin_decision in ('APPROVED', 'DENIED')),
  last_admin_decision_at timestamptz,
  last_admin_decision_by uuid references public.profiles(id) on delete set null,
  admin_decision_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists gc_tutor_membership_state_tier_idx
  on public.gc_tutor_membership_controls (account_state, plan_tier);

create index if not exists gc_tutor_membership_last_tuition_idx
  on public.gc_tutor_membership_controls (last_verified_tuition_at);

comment on table public.gc_tutor_membership_controls is
  'Admin-controlled tutor tier and listing/freeze state. Existing public IDs and core workflow IDs remain unchanged.';
comment on column public.gc_tutor_membership_controls.plan_tier is
  'UNCLASSIFIED until an administrator confirms the actual tutor plan. Do not derive from generic paid_status.';
comment on column public.gc_tutor_membership_controls.last_verified_tuition_at is
  'Must only be updated from verified real tuition activity, never from GURU Coin or Learning Request escrow events.';
comment on column public.gc_tutor_membership_controls.revenue_share_rate is
  'Configured revenue-share rate; default 5%. This field alone does not record or charge money.';

-- A real tuition event is separate from GURU Coin escrow and LRR activity.
-- Insert only after the tuition/revenue information has been verified by Admin.
create table if not exists public.gc_tutor_tuition_events (
  id uuid primary key default gen_random_uuid(),
  tutor_user_id uuid not null references public.profiles(id) on delete restrict,
  tuition_date timestamptz not null,
  gross_revenue numeric(12,2) not null check (gross_revenue >= 0),
  currency text not null default 'INR',
  revenue_share_rate numeric(5,4) not null default 0.0500
    check (revenue_share_rate >= 0 and revenue_share_rate <= 1),
  revenue_share_amount numeric(12,2) generated always as
    (round(gross_revenue * revenue_share_rate, 2)) stored,
  verification_status text not null default 'PENDING'
    check (verification_status in ('PENDING', 'VERIFIED', 'REJECTED')),
  revenue_share_payment_status text not null default 'NOT_RECORDED'
    check (revenue_share_payment_status in ('NOT_RECORDED', 'DUE', 'PAID', 'WAIVED')),
  evidence_reference text,
  admin_note text,
  verified_by uuid references public.profiles(id) on delete set null,
  verified_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists gc_tutor_tuition_events_tutor_date_idx
  on public.gc_tutor_tuition_events (tutor_user_id, tuition_date desc);

create index if not exists gc_tutor_tuition_events_verification_idx
  on public.gc_tutor_tuition_events (verification_status, revenue_share_payment_status);

comment on table public.gc_tutor_tuition_events is
  'Admin-verified real tuition/revenue records used for 5% revenue-share accounting. Never populate from GURU Coin transactions.';

-- Relisting requests are separate records so Admin decisions remain reviewable.
create table if not exists public.gc_tutor_relisting_requests (
  id uuid primary key default gen_random_uuid(),
  tutor_user_id uuid not null references public.profiles(id) on delete restrict,
  requested_at timestamptz not null default now(),
  tutor_note text,
  status text not null default 'PENDING'
    check (status in ('PENDING', 'APPROVED', 'DENIED', 'WITHDRAWN')),
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  admin_note text
);

create index if not exists gc_tutor_relisting_requests_review_idx
  on public.gc_tutor_relisting_requests (status, requested_at);

comment on table public.gc_tutor_relisting_requests is
  'Audit trail for tutor requests to be relisted after a freeze. Admin must review history before approval.';

-- This foundation is intentionally not writable from browser clients.
-- A follow-up, tested admin-authorized RPC/UI must be added before activation.
alter table public.gc_tutor_membership_controls enable row level security;
alter table public.gc_tutor_tuition_events enable row level security;
alter table public.gc_tutor_relisting_requests enable row level security;

revoke all on table public.gc_tutor_membership_controls from anon, authenticated;
revoke all on table public.gc_tutor_tuition_events from anon, authenticated;
revoke all on table public.gc_tutor_relisting_requests from anon, authenticated;
