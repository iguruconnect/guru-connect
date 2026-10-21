-- GURU CONNECT: rejected pre-work connection requests release the LRR for another tutor.
-- A rejection is only allowed while the connection is pending. If the LRR is still
-- within its 20-day validity window, clear the tutor assignment and reopen it.
-- If the 20-day window has expired, mark it EXPIRED instead. No coin or ledger
-- tables are touched by this migration.

BEGIN;

CREATE OR REPLACE FUNCTION public.gc_student_reject_learning_connection(
    p_connection_id uuid
)
RETURNS public.gc_learning_request_connections
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_student public.student_profiles%ROWTYPE;
    v_conn public.gc_learning_request_connections%ROWTYPE;
    v_request public.gc_learning_requests%ROWTYPE;
    v_subject text;
    v_tutor_user_id uuid;
    v_student_member_id uuid;
    v_tutor_name text;
BEGIN
    SELECT *
      INTO v_student
    FROM public.student_profiles
    WHERE user_id = auth.uid()
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Registered Student login required.';
    END IF;

    SELECT *
      INTO v_conn
    FROM public.gc_learning_request_connections
    WHERE id = p_connection_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Connection request not found.';
    END IF;

    IF v_conn.student_id <> v_student.id THEN
        RAISE EXCEPTION 'You are not allowed to reject this connection.';
    END IF;

    IF v_conn.status <> 'PENDING_STUDENT' THEN
        RAISE EXCEPTION 'This connection request is no longer pending.';
    END IF;

    SELECT *
      INTO v_request
    FROM public.gc_learning_requests
    WHERE id = v_conn.request_id::text
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Learning Request not found.';
    END IF;

    SELECT tp.user_id, tp.name
      INTO v_tutor_user_id, v_tutor_name
    FROM public.tutor_profiles tp
    WHERE tp.id = v_conn.tutor_id
    LIMIT 1;

    IF v_tutor_user_id IS NULL THEN
        RAISE EXCEPTION 'Tutor canonical account mapping is missing.';
    END IF;

    v_student_member_id := v_student.user_id;
    v_subject := coalesce(nullif(trim(v_request.subject), ''), 'Learning Request');

    UPDATE public.gc_learning_request_connections
    SET status = 'REJECTED',
        responded_at = now()
    WHERE id = v_conn.id
    RETURNING * INTO v_conn;

    -- Any other pending connection attempt for this same LRR is also stale.
    UPDATE public.gc_learning_request_connections
    SET status = 'REJECTED',
        responded_at = now()
    WHERE request_id = v_conn.request_id
      AND id <> v_conn.id
      AND status = 'PENDING_STUDENT';

    -- Release the tutor claim. The LRR is reusable only during its original
    -- 20-day validity window; rejection never extends that original window.
    IF v_request.created_at IS NOT NULL
       AND v_request.created_at + interval '20 days' > now() THEN
        UPDATE public.gc_learning_requests
        SET tutor_id = NULL,
            status = 'OPEN'
        WHERE id = v_conn.request_id::text;
    ELSE
        UPDATE public.gc_learning_requests
        SET tutor_id = NULL,
            status = 'EXPIRED'
        WHERE id = v_conn.request_id::text;
    END IF;

    INSERT INTO public.gc_notifications(
        recipient_profile_id, recipient_role, sender_profile_id,
        type, title, body, request_id, connection_id
    )
    VALUES (
        v_tutor_user_id,
        'tutor',
        v_student_member_id,
        'CONNECTION_RESPONSE',
        'Connection Rejected',
        coalesce(nullif(trim(v_student.name), ''), 'Student')
          || ' rejected your connection request for ' || v_subject
          || CASE
               WHEN v_request.created_at IS NOT NULL
                AND v_request.created_at + interval '20 days' > now()
               THEN '. The Learning Request is open again for another Tutor.'
               ELSE '. The Learning Request has passed its 20-day validity and is expired.'
             END,
        v_conn.request_id,
        v_conn.id
    );

    RETURN v_conn;
END;
$function$;

COMMIT;

-- Verification (read-only):
-- SELECT pg_get_functiondef('public.gc_student_reject_learning_connection(uuid)'::regprocedure);
