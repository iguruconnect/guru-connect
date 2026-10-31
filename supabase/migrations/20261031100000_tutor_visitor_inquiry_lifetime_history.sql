-- GURU CONNECT: lifetime history for visitor inquiries delivered to a Premium Tutor.
-- Read-only. Does not update or delete inquiry/LRR records, wallets, escrow, or coin ledger.
create or replace function public.gc_tutor_visitor_inquiry_history_list()
returns setof public.gc_tutor_requirements
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tutor_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Please log in with an eligible Premium Tutor account.';
  end if;

  if not exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and lower(coalesce(p.role::text,'')) = 'tutor'
  ) then
    raise exception 'This section is available only to Tutors.';
  end if;

  select t.id into v_tutor_id
  from public.tutor_profiles t
  where t.user_id = auth.uid()
    and lower(coalesce(t.payment_plan,'')) in ('premium_200','premium_verified_300')
    and upper(coalesce(t.paid_status,'')) = 'PAID'
    and coalesce(t.is_hidden,false) = false
    and coalesce(t.is_disabled,false) = false
  limit 1;

  if v_tutor_id is null then
    raise exception 'Tutor Inquiry history is available only to active Premium Tutors with confirmed payment.';
  end if;

  return query
    select r.*
    from public.gc_tutor_requirements r
    inner join public.gc_tutor_requirement_recipients x
      on x.requirement_id = r.id
     and x.tutor_profile_id = v_tutor_id
    where upper(coalesce(r.requirement_source,'')) = 'VISITOR'
    order by r.created_at desc;
end;
$$;

revoke all on function public.gc_tutor_visitor_inquiry_history_list() from public, anon;
grant execute on function public.gc_tutor_visitor_inquiry_history_list() to authenticated;

notify pgrst, 'reload schema';
