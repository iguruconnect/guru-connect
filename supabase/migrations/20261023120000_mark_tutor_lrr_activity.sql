-- GURU CONNECT: count tutor participation in an LRR as qualifying Free-plan activity.
-- This migration only records activity timestamps. It does NOT hide profiles or alter
-- LRR statuses, coin balances, connection records, or existing workflow rules.
-- Apply only after reviewing this migration and the related membership migration.

begin;

create or replace function public.gc_mark_tutor_lrr_activity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tutor_key text;
  v_status text;
begin
  v_tutor_key := nullif(btrim(coalesce(NEW.tutor_id::text, '')), '');
  v_status := upper(coalesce(NEW.status, ''));

  -- OPEN requests are public opportunities, not engagement by a specific tutor.
  -- Once a tutor is assigned and the request has moved beyond OPEN, count it as
  -- engagement. This includes PENDING_STUDENT_CONNECTION / TUTOR_ACCEPTED and
  -- later in-progress/completion review stages.
  if v_tutor_key is not null
     and v_status not in ('', 'OPEN', 'CANCELLED', 'CANCELED', 'REJECTED', 'DECLINED', 'EXPIRED') then
    update public.tutor_profiles tp
       set free_last_qualifying_activity_at = now(),
           profile_hidden = false,
           profile_hidden_reason = null
     where tp.id::text = v_tutor_key
        or tp.user_id::text = v_tutor_key;
  end if;

  return NEW;
end;
$$;

drop trigger if exists trg_gc_mark_tutor_lrr_activity on public.gc_learning_requests;
create trigger trg_gc_mark_tutor_lrr_activity
after insert or update of tutor_id, status
on public.gc_learning_requests
for each row
execute function public.gc_mark_tutor_lrr_activity();

commit;
