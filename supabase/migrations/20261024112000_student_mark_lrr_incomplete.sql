BEGIN;

-- Let a Student return a Tutor-completed LRR to active work when the work is not finished.
-- This does not release or modify held coins, wallets, or the coin ledger.
CREATE OR REPLACE FUNCTION public.gc_student_mark_learning_request_incomplete(
    p_request_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_uid uuid := auth.uid();
    v_tutor_uid uuid;
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

    IF r.student_member_id IS NULL
       OR r.student_member_id::text <> v_uid::text THEN
        RAISE EXCEPTION 'Only the Student who owns this LRR can mark it incomplete.';
    END IF;

    IF upper(coalesce(r.status, '')) <> 'TUTOR_COMPLETED' THEN
        RAISE EXCEPTION 'This LRR is not waiting for Student completion confirmation.';
    END IF;

    IF r.student_reviewed_at IS NOT NULL THEN
        RAISE EXCEPTION 'Student confirmation has already been recorded.';
    END IF;

    v_tutor_uid := NULLIF(r.tutor_member_id::text, '')::uuid;

    IF v_tutor_uid IS NULL AND r.tutor_id IS NOT NULL THEN
        SELECT tp.user_id
          INTO v_tutor_uid
        FROM public.tutor_profiles AS tp
        WHERE tp.id::text = r.tutor_id::text
        LIMIT 1;
    END IF;

    IF v_tutor_uid IS NULL THEN
        RAISE EXCEPTION 'The Tutor account mapping is missing. Please contact Admin; no changes were made.';
    END IF;

    UPDATE public.gc_learning_requests
       SET status = 'TUTOR_ACCEPTED',
           student_outcome = 'INCOMPLETE',
           student_reviewed_at = NULL
     WHERE id = p_request_id::text
     RETURNING * INTO r;

    INSERT INTO public.gc_notifications(
        recipient_profile_id,
        recipient_role,
        sender_profile_id,
        type,
        title,
        body,
        request_id
    )
    VALUES (
        v_tutor_uid,
        'tutor',
        v_uid,
        'LRR_MARKED_INCOMPLETE',
        'Student marked the work incomplete',
        'The Student has marked this Learning Request as incomplete. Please continue the work and mark it completed again only when it is finished.',
        p_request_id
    );

    RETURN to_jsonb(r);
END;
$function$;

REVOKE ALL ON FUNCTION public.gc_student_mark_learning_request_incomplete(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gc_student_mark_learning_request_incomplete(uuid) TO authenticated;

COMMIT;
