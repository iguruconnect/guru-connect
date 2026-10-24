-- GURU CONNECT: let either participant leave an active engagement with a required reason.
-- The other participant is notified, the reason is retained for history, and the LRR
-- reopens only inside its original 20-day window. Wallets, escrow, and coin ledger
-- are intentionally not changed by this workflow.

BEGIN;

ALTER TABLE public.gc_learning_request_connections
  ADD COLUMN IF NOT EXISTS left_at timestamptz,
  ADD COLUMN IF NOT EXISTS left_by uuid,
  ADD COLUMN IF NOT EXISTS left_by_role text,
  ADD COLUMN IF NOT EXISTS left_reason text;

CREATE OR REPLACE FUNCTION public.gc_leave_learning_engagement(
  p_connection_id uuid,
  p_reason text
)
RETURNS public.gc_learning_request_connections
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_conn public.gc_learning_request_connections%ROWTYPE;
  v_request public.gc_learning_requests%ROWTYPE;
  v_student_id uuid;
  v_tutor_id uuid;
  v_student_user_id uuid;
  v_tutor_user_id uuid;
  v_student_name text;
  v_tutor_name text;
  v_actor_role text;
  v_recipient uuid;
  v_actor_name text;
  v_subject text;
  v_still_valid boolean;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Please log in again before leaving this engagement.';
  END IF;
  IF v_reason IS NULL OR length(v_reason) < 5 THEN
    RAISE EXCEPTION 'Please enter a reason of at least 5 characters.';
  END IF;
  IF length(v_reason) > 1000 THEN
    RAISE EXCEPTION 'The reason must be 1000 characters or fewer.';
  END IF;

  SELECT sp.id, sp.user_id, coalesce(nullif(btrim(sp.name), ''), 'Student')
    INTO v_student_id, v_student_user_id, v_student_name
  FROM public.student_profiles sp
  WHERE sp.user_id = v_uid
  LIMIT 1;

  SELECT tp.id, tp.user_id, coalesce(nullif(btrim(tp.name), ''), 'Tutor')
    INTO v_tutor_id, v_tutor_user_id, v_tutor_name
  FROM public.tutor_profiles tp
  WHERE tp.user_id = v_uid
  LIMIT 1;

  SELECT * INTO v_conn
  FROM public.gc_learning_request_connections
  WHERE id = p_connection_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Connection not found.';
  END IF;

  IF v_student_id IS NOT NULL
     AND (v_conn.student_id = v_student_id OR v_conn.student_member_id = v_uid) THEN
    v_actor_role := 'student';
    v_actor_name := v_student_name;
    v_recipient := v_tutor_user_id;
  ELSIF v_tutor_id IS NOT NULL
     AND (v_conn.tutor_id = v_tutor_id OR v_conn.tutor_member_id = v_uid) THEN
    v_actor_role := 'tutor';
    v_actor_name := v_tutor_name;
    v_recipient := v_student_user_id;
  ELSE
    RAISE EXCEPTION 'Only the Student or Tutor in this engagement can leave it.';
  END IF;

  IF upper(coalesce(v_conn.status, '')) NOT IN
     ('ACCEPTED','CONNECTED','TUTOR_ACCEPTED','IN_PROGRESS') THEN
    RAISE EXCEPTION 'Only an active engagement can be left with this action. Pending requests use Accept/Reject; completed or review cases must follow the existing review process.';
  END IF;

  SELECT * INTO v_request
  FROM public.gc_learning_requests
  WHERE id::text = v_conn.request_id::text
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Learning Request not found.';
  END IF;

  IF upper(coalesce(v_request.status, '')) IN
     ('COMPLETED','SOLVED','APPROVED','ADMIN_APPROVED','ADMIN_DENIED',
      'REJECTED_BY_ADMIN','RETURNED_TO_STUDENT','CANCELLED','CANCELED',
      'DELETED','EXPIRED','DISPUTED','UNDER_REVIEW','PENDING_ADMIN_REVIEW',
      'PENDING_ADMIN_APPROVAL')
     OR upper(coalesce(v_request.gc_cancellation_status, '')) = 'PENDING_ADMIN_REVIEW'
     OR upper(coalesce(to_jsonb(v_request)->>'student_outcome', '')) = 'NOT_SATISFIED' THEN
    RAISE EXCEPTION 'This Learning Request is completed, closed, disputed, or under Admin review. Please use the existing review process.';
  END IF;

  v_subject := coalesce(nullif(btrim(v_request.subject), ''), 'Learning Request');
  v_still_valid := v_request.created_at IS NOT NULL
                   AND v_request.created_at + interval '20 days' > now();

  UPDATE public.gc_learning_request_connections
  SET status = 'LEFT_ENGAGEMENT',
      left_at = now(),
      left_by = v_uid,
      left_by_role = v_actor_role,
      left_reason = v_reason,
      responded_at = now()
  WHERE id = v_conn.id
  RETURNING * INTO v_conn;

  -- Clear the tutor assignment and release the LRR; never extend the original validity.
  UPDATE public.gc_learning_requests
  SET tutor_id = NULL,
      status = CASE WHEN v_still_valid THEN 'OPEN' ELSE 'EXPIRED' END
  WHERE id::text = v_conn.request_id::text;

  IF v_recipient IS NOT NULL THEN
    INSERT INTO public.gc_notifications(
      recipient_profile_id, recipient_role, sender_profile_id,
      type, title, body, request_id, connection_id
    )
    VALUES (
      v_recipient,
      CASE WHEN v_actor_role = 'student' THEN 'tutor' ELSE 'student' END,
      v_uid,
      'CONNECTION_RESPONSE',
      'Engagement Left',
      v_actor_name || ' left the engagement for "' || v_subject || '". Reason: '
        || v_reason
        || CASE WHEN v_still_valid
             THEN '. The Learning Request is open again for another Tutor.'
             ELSE '. The original 20-day validity has expired, so the Learning Request is not available for reconnection.'
           END,
      v_conn.request_id,
      v_conn.id
    );
  END IF;

  RETURN v_conn;
END;
$function$;

REVOKE ALL ON FUNCTION public.gc_leave_learning_engagement(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gc_leave_learning_engagement(uuid, text) TO authenticated;

COMMIT;

-- Read-only verification after applying:
-- SELECT pg_get_functiondef('public.gc_leave_learning_engagement(uuid,text)'::regprocedure);
