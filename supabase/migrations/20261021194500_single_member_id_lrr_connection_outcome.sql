-- GURU CONNECT: canonical account IDs for LRR outcome checks and notifications
-- Keep gc_learning_request_connections.student_id/tutor_id as detail-profile IDs:
-- those columns have foreign keys to student_profiles.id and tutor_profiles.id.
-- This migration does not move coins, alter balances, or rewrite existing requests.

BEGIN;

CREATE OR REPLACE FUNCTION public.gc_student_learning_request_outcome(
    p_request_id uuid,
    p_outcome text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_uid uuid := auth.uid();
    v_outcome text := upper(trim(coalesce(p_outcome, '')));
    r public.gc_learning_requests%ROWTYPE;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Please login first.';
    END IF;

    SELECT *
      INTO r
    FROM public.gc_learning_requests
    WHERE id = p_request_id::text
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Learning Request not found.';
    END IF;

    -- Authorize by canonical account ID; retain legacy student_id for its
    -- existing detail-profile relationship and display behavior.
    IF r.student_member_id IS NULL
       OR r.student_member_id::text <> v_uid::text THEN
        RAISE EXCEPTION 'You are not the Student for this request.';
    END IF;

    IF upper(coalesce(r.status, '')) <> 'TUTOR_COMPLETED' THEN
        RAISE EXCEPTION
            'Tutor must complete the Learning Request before Student confirmation.';
    END IF;

    IF r.student_reviewed_at IS NOT NULL THEN
        RAISE EXCEPTION 'Student review has already been recorded.';
    END IF;

    IF v_outcome NOT IN (
        'SATISFIED', 'NOT_SATISFIED',
        'COMPLETED_SATISFIED', 'COMPLETED_NOT_SATISFIED'
    ) THEN
        RAISE EXCEPTION 'Outcome must be SATISFIED or NOT_SATISFIED.';
    END IF;

    UPDATE public.gc_learning_requests
    SET student_outcome = CASE
            WHEN v_outcome IN ('SATISFIED', 'COMPLETED_SATISFIED')
                THEN 'COMPLETED_SATISFIED'
            ELSE 'COMPLETED_NOT_SATISFIED'
        END,
        student_reviewed_at = now(),
        status = 'AWAITING ADMIN REVIEW'
    WHERE id = p_request_id::text
    RETURNING * INTO r;

    RETURN to_jsonb(r);
END;
$function$;

CREATE OR REPLACE FUNCTION public.gc_tutor_send_learning_connection(
    p_request_id uuid
)
RETURNS public.gc_learning_request_connections
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_tutor public.tutor_profiles%ROWTYPE;
    v_request public.gc_learning_requests_v2%ROWTYPE;
    v_conn public.gc_learning_request_connections%ROWTYPE;
    v_subject text;
    v_student_member_id uuid;
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
      INTO v_request
    FROM public.gc_learning_requests_v2
    WHERE id = p_request_id::text;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Learning Request not found.';
    END IF;

    IF v_request.tutor_id IS NOT NULL
       AND v_request.tutor_id <> v_tutor.id::text THEN
        RAISE EXCEPTION 'This Learning Request already has a Tutor.';
    END IF;

    IF coalesce(v_request.status, 'OPEN')
       NOT IN ('OPEN', 'PENDING_STUDENT_CONNECTION') THEN
        RAISE EXCEPTION
            'This Learning Request is not available for a new connection request.';
    END IF;

    IF v_request.student_id IS NULL OR v_request.student_member_id IS NULL THEN
        RAISE EXCEPTION 'Student account mapping is missing; no connection created.';
    END IF;

    v_student_member_id := v_request.student_member_id::uuid;

    INSERT INTO public.gc_learning_request_connections(
        request_id, student_id, tutor_id, status
    )
    VALUES (
        v_request.id::uuid,
        v_request.student_id::uuid,
        v_tutor.id,
        'PENDING_STUDENT'
    )
    ON CONFLICT (request_id, tutor_id)
    DO UPDATE SET status = 'PENDING_STUDENT',
                  responded_at = NULL
    RETURNING * INTO v_conn;

    UPDATE public.gc_learning_requests
    SET status = 'PENDING_STUDENT_CONNECTION'
    WHERE id = v_request.id
      AND tutor_id IS NULL
      AND coalesce(status, 'OPEN') = 'OPEN';

    v_subject := coalesce(nullif(trim(v_request.subject), ''), 'Learning Request');

    -- Notification identity fields use canonical account IDs, while the
    -- connection row above deliberately retains detail-profile IDs.
    INSERT INTO public.gc_notifications(
        recipient_profile_id, recipient_role, sender_profile_id,
        type, title, body, request_id, connection_id
    )
    VALUES (
        v_student_member_id,
        'student',
        v_tutor.user_id,
        'CONNECTION_REQUEST',
        'New Tutor Connection Request',
        coalesce(nullif(trim(v_tutor.name), ''), 'A Tutor')
          || ' wants to connect for ' || v_subject
          || '. Open Connection Requests to ACCEPT or REJECT.',
        v_conn.request_id,
        v_conn.id
    );

    RETURN v_conn;
END;
$function$;

COMMIT;

-- Read-only post-deployment signature check:
-- SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS arguments,
--        pg_get_function_result(p.oid) AS result
-- FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
-- WHERE n.nspname = 'public'
--   AND p.proname IN ('gc_student_learning_request_outcome',
--                     'gc_tutor_send_learning_connection')
-- ORDER BY p.proname, arguments;
