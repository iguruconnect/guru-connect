-- GURU CONNECT Advertisement System
-- Run once in Supabase SQL Editor before using Admin > Advertisements.

create extension if not exists pgcrypto;

create table if not exists public.gc_advertisements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  advertiser_name text,
  placement text not null default 'all' check (placement in ('lrr','student','tutor','all')),
  image_url text not null,
  storage_path text,
  click_url text,
  whatsapp_url text,
  start_at timestamptz default now(),
  end_at timestamptz,
  active boolean not null default true,
  priority integer not null default 0,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists gc_ads_active_idx on public.gc_advertisements(active, placement, priority desc, created_at desc);

alter table public.gc_advertisements enable row level security;

-- Public website: only active, date-valid ads are visible.
drop policy if exists "gc_ads_public_active_select" on public.gc_advertisements;
create policy "gc_ads_public_active_select"
on public.gc_advertisements for select
using (
  active = true
  and (start_at is null or start_at <= now())
  and (end_at is null or end_at >= now())
);

-- Staff/Admin full management. Existing GURU CONNECT Staff/Admin UID is used by the project.
drop policy if exists "gc_ads_admin_all" on public.gc_advertisements;
create policy "gc_ads_admin_all"
on public.gc_advertisements for all
using (lower(coalesce(auth.jwt() ->> 'email','')) = 'guruconnect.in@gmail.com')
with check (lower(coalesce(auth.jwt() ->> 'email','')) = 'guruconnect.in@gmail.com');

-- Storage bucket for advertiser flyers.
insert into storage.buckets (id,name,public)
values ('gc-advertisements','gc-advertisements',true)
on conflict (id) do update set public=true;

drop policy if exists "gc_ads_storage_public_read" on storage.objects;
create policy "gc_ads_storage_public_read"
on storage.objects for select
using (bucket_id = 'gc-advertisements');

drop policy if exists "gc_ads_storage_admin_insert" on storage.objects;
create policy "gc_ads_storage_admin_insert"
on storage.objects for insert
with check (bucket_id = 'gc-advertisements' and lower(coalesce(auth.jwt() ->> 'email','')) = 'guruconnect.in@gmail.com');

drop policy if exists "gc_ads_storage_admin_update" on storage.objects;
create policy "gc_ads_storage_admin_update"
on storage.objects for update
using (bucket_id = 'gc-advertisements' and lower(coalesce(auth.jwt() ->> 'email','')) = 'guruconnect.in@gmail.com')
with check (bucket_id = 'gc-advertisements' and lower(coalesce(auth.jwt() ->> 'email','')) = 'guruconnect.in@gmail.com');

drop policy if exists "gc_ads_storage_admin_delete" on storage.objects;
create policy "gc_ads_storage_admin_delete"
on storage.objects for delete
using (bucket_id = 'gc-advertisements' and lower(coalesce(auth.jwt() ->> 'email','')) = 'guruconnect.in@gmail.com');
