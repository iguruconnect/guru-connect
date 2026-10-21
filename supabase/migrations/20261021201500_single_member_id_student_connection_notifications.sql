-- GURU CONNECT: keep student accept/reject notifications on canonical account IDs.
-- Connection rows retain detail-profile IDs because their foreign keys require them.
-- This migration changes notification identities only; it does not change coin balances.

BEGIN;

CREATE OR REPLACE FUNCTION public.gc_student_accept_learning_connection(
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
    v_request public.gc_learning_requests_v2%ROWTYPE;
    v_subject text;
    v_tutor_user_id uuid;
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
        RAISE EXCEPTION 'You are not allowed to accept this connection.';
    END IF;

    IF v_conn.status <> 'PENDING_STUDENT' THEN
        RAISE EXCEPTION 'This connection request is no longer pending.';
    END IF;

    SELECT *
      INTO v_request
    FROM public.gc_learning_requests_v2
    WHERE id = v_conn.request_id::text;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Learning Request not found.';
    END IF;

    IF v_request.tutor_id IS NOT NULL
       AND v_request.tutor_id <> v_conn.tutor_id::text THEN
        RAISE EXCEPTION 'Another Tutor is already connected to this request.';
    END IF;

    SELECT tp.user_id
      INTO v_tutor_user_id
    FROM public.tutor_profiles tp
    WHERE tp.id = v_conn.tutor_id
    LIMIT 1;

    IF v_tutor_user_id IS NULL THEN
        RAISE EXCEPTION 'Tutor canonical account mapping is missing.';
    END IF;

    UPDATE public.gc_learning_request_connections
    SET status = 'ACCEPTED',
        responded_at = now()
    WHERE id = v_conn.id
    RETURNING * INTO v_conn;

    UPDATE public.gc_learning_request_connections
    SET status = 'REJECTED',
        responded_at = now()
    WHERE request_id = v_conn.request_id
      AND id <> v_conn.id
      AND status = 'PENDING_STUDENT';

    UPDATE public.gc_learning_requests
    SET tutor_id = v_conn.tutor_id::text,
        status = 'TUTOR_ACCEPTED'
    WHERE id = v_conn.request_id::text;

    v_subject := coalesce(nullif(trim(v_request.subject), ''), 'Learning Request');

    INSERT INTO public.gc_notifications(
        recipient_profile_id, recipient_role, sender_profile_id,
        type, title, body, request_id, connection_id
    )
    VALUES (
        v_tutor_user_id,
        'tutor',
        v_student.user_id,
        'CONNECTION_RESPONSE',
        'Connection Accepted',
        coalesce(nullif(trim(v_student.name), ''), 'Student')
          || ' accepted your connection request for ' || v_subject
          || '. Private chat is now active.',
        v_conn.request_id,
        v_conn.id
    );

    RETURN v_conn;
END;
$function$;

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
    v_request public.gc_learning_requests_v2%ROWTYPE;
    v_subject text;
    v_tutor_user_id uuid;
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
    FROM public.gc_learning_requests_v2
    WHERE id = v_conn.request_id::text;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Learning Request not found.';
    END IF;

    SELECT tp.user_id
      INTO v_tutor_user_id
    FROM public.tutor_profiles tp
    WHERE tp.id = v_conn.tutor_id
    LIMIT 1;

    IF v_tutor_user_id IS NULL THEN
        RAISE EXCEPTION 'Tutor canonical account mapping is missing.';
    END IF;

    UPDATE public.gc_learning_request_connections
    SET status = 'REJECTED',
        responded_at = now()
    WHERE id = v_conn.id
    RETURNING * INTO v_conn;

    v_subject := coalesce(nullif(trim(v_request.subject), ''), 'Learning Request');

    INSERT INTO public.gc_notifications(
        recipient_profile_id, recipient_role, sender_profile_id,
        type, title, body, request_id, connection_id
    )
    VALUES (
        v_tutor_user_id,
        'tutor',
        v_student.user_id,
        'CONNECTION_RESPONSE',
        'Connection Rejected',
        coalesce(nullif(trim(v_student.name), ''), 'Student')
          || ' rejected your connection request for ' || v_subject || '.',
        v_conn.request_id,
        v_conn.id
    );

    RETURN v_conn;
END;
$function$;

COMMIT;

-- Read-only verification:
-- SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS arguments,
--        pg_get_functiondef(p.oid) ILIKE '%v_tutor_user_id%' AS canonical_notification_sender_and_recipient
-- FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
-- WHERE n.nspname = 'public'
--   AND p.proname IN ('gc_student_accept_learning_connection',
--                     'gc_student_reject_learning_connection')
-- ORDER BY p.proname;
