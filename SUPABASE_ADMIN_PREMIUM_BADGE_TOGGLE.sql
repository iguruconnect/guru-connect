-- GURU CONNECT: Admin ON/OFF control for Premium badge on tutor profile cards.
-- This is a profile-display override only. It does NOT mark payment as PAID,
-- grant the Verified Tick, or change visitor inquiry eligibility.
-- Does not touch Learning Requests, GURU Coins, wallets, escrow, connections or chat.

alter table public.tutor_profiles
  add column if not exists premium_badge_override boolean default null;

create or replace function public.gc_admin_set_premium_badge(
  p_user_id uuid,
  p_enabled boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_rows integer;
begin
  -- Match the site's existing Admin/Staff authorization conventions.
  -- The Admin dashboard may authenticate staff through JWT metadata or the
  -- configured admin account rather than profiles.role='admin'.
  if auth.uid() is null or not (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and lower(coalesce(p.role::text,'')) in ('admin','staff')
    )
    or lower(coalesce(auth.jwt()->'user_metadata'->>'role','')) in ('admin','staff')
    or lower(coalesce(auth.jwt()->'app_metadata'->>'role','')) in ('admin','staff')
    or lower(coalesce(auth.jwt()->>'email','')) = 'guruconnect.in@gmail.com'
    or lower(coalesce(auth.jwt()->'user_metadata'->>'is_staff','')) = 'true'
    or lower(coalesce(auth.jwt()->'app_metadata'->>'is_staff','')) = 'true'
  ) then
    raise exception 'Admin/Staff authorization required to change Premium badge.';
  end if;

  update public.tutor_profiles
     set premium_badge_override = p_enabled
   where user_id = p_user_id;

  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    raise exception 'Tutor profile not found for this user ID.';
  end if;

  return jsonb_build_object(
    'success', true,
    'user_id', p_user_id,
    'premium_badge_override', p_enabled
  );
end;
$$;

revoke all on function public.gc_admin_set_premium_badge(uuid, boolean) from public;
grant execute on function public.gc_admin_set_premium_badge(uuid, boolean) to authenticated;

notify pgrst, 'reload schema';
