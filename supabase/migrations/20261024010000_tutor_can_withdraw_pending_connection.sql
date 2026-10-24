-- GURU CONNECT: let the Tutor withdraw/reject their own pending connection request.
-- A rejected pending connection releases the LRR for another Tutor during its original
-- 20-day window. Existing accepted/active-connection cancellation remains unchanged.
-- No coin wallet, escrow, or ledger tables are touched.

BEGIN;

CREATE OR REPLACE FUNCTION public.gc_tutor_reject_learning_connection(
    p_connection_id uuid
)
RETURNS public.gc_learning_request_connections
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_tutor public.tutor_profiles%ROWTYPE;
    v_conn public.gc_learning_request_connections%ROWTYPE;
    v_request public.gc_learning_requests%ROWTYPE;
    v_student_user_id uuid;
    v_student_name text;
    v_subject text;
    v_still_valid boolean;
BEGIN
    SELECT *
      INTO v_tutor
    FROM public.tutor_profiles
    WHERE user_id = auth.uid()
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Registered Tutor login required.';
    END IF;

    SELECT *
      INTO v_conn
    FROM public.gc_learning_request_connections
    WHERE id = p_connection_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Connection request not found.';
    END IF;

    IF v_conn.tutor_id IS DISTINCT FROM v_tutor.id THEN
        RAISE EXCEPTION 'You are not allowed to withdraw this connection request.';
    END IF;

    IF upper(coalesce(v_conn.status, '')) NOT IN ('PENDING_STUDENT', 'PENDING', 'REQUESTED') THEN
        RAISE EXCEPTION 'Only a pending connection request can be withdrawn. Use the existing cancellation process for an active connection.';
    END IF;

    SELECT *
      INTO v_request
    FROM public.gc_learning_requests
    WHERE id::text = v_conn.request_id::text
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Learning Request not found.';
    END IF;

    IF upper(coalesce(v_request.status, '')) IN
       ('COMPLETED','SOLVED','APPROVED','ADMIN_APPROVED','ADMIN_DENIED','REJECTED_BY_ADMIN',
        'RETURNED_TO_STUDENT','CANCELLED','CANCELED','DELETED','EXPIRED')
       OR upper(coalesce(v_request.gc_cancellation_status, '')) = 'PENDING_ADMIN_REVIEW'
       OR upper(coalesce(to_jsonb(v_request)->>'student_outcome', '')) = 'NOT_SATISFIED' THEN
        RAISE EXCEPTION 'This Learning Request is closed or under Admin review and cannot be reopened.';
    END IF;

    SELECT sp.user_id, coalesce(nullif(trim(sp.name), ''), 'Student')
      INTO v_student_user_id, v_student_name
    FROM public.student_profiles sp
    WHERE sp.id = v_conn.student_id
    LIMIT 1;

    IF v_student_user_id IS NULL THEN
        RAISE EXCEPTION 'Student canonical account mapping is missing.';
    END IF;

    v_subject := coalesce(nullif(trim(v_request.subject), ''), 'Learning Request');
    v_still_valid := v_request.created_at IS NOT NULL
                     AND v_request.created_at + interval '20 days' > now();

    UPDATE public.gc_learning_request_connections
       SET status = 'REJECTED',
           responded_at = now()
     WHERE id = v_conn.id
     RETURNING * INTO v_conn;

    -- Other pending attempts for this same LRR are stale once one party rejects.
    UPDATE public.gc_learning_request_connections
       SET status = 'REJECTED',
           responded_at = now()
     WHERE request_id = v_conn.request_id
       AND id <> v_conn.id
       AND upper(coalesce(status, '')) IN ('PENDING_STUDENT','PENDING','REQUESTED');

    UPDATE public.gc_learning_requests
       SET tutor_id = NULL,
           status = CASE WHEN v_still_valid THEN 'OPEN' ELSE 'EXPIRED' END
     WHERE id::text = v_conn.request_id::text;

    INSERT INTO public.gc_notifications(
        recipient_profile_id, recipient_role, sender_profile_id,
        type, title, body, request_id, connection_id
    )
    VALUES (
        v_student_user_id,
        'student',
        v_tutor.user_id,
        'CONNECTION_RESPONSE',
        'Connection Request Withdrawn',
        coalesce(nullif(trim(v_tutor.name), ''), 'Tutor')
          || ' withdrew the connection request for ' || v_subject
          || CASE
               WHEN v_still_valid
               THEN '. Your Learning Request is open again for another Tutor.'
               ELSE '. The Learning Request has passed its original 20-day validity and is expired.'
             END,
        v_conn.request_id,
        v_conn.id
    );

    RETURN v_conn;
END;
$function$;

REVOKE ALL ON FUNCTION public.gc_tutor_reject_learning_connection(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gc_tutor_reject_learning_connection(uuid) TO authenticated;

COMMIT;

-- Read-only verification after applying:
-- SELECT pg_get_functiondef('public.gc_tutor_reject_learning_connection(uuid)'::regprocedure);
