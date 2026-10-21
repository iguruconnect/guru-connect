-- GURU CONNECT: safe dashboard removal for closed Learning Requests and Connection Requests.
-- Keeps database history and coin balances/ledger unchanged.
ALTER TABLE public.gc_learning_requests
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz,
  ADD COLUMN IF NOT EXISTS deleted_by uuid;

ALTER TABLE public.gc_learning_request_connections
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz,
  ADD COLUMN IF NOT EXISTS deleted_by uuid;

CREATE OR REPLACE FUNCTION public.gc_delete_learning_request_record(p_request_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  r public.gc_learning_requests%ROWTYPE;
  v_status text;
  v_admin_decision text;
  v_is_student boolean := false;
  v_is_tutor boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Please log in again.';
  END IF;

  SELECT * INTO r
  FROM public.gc_learning_requests
  WHERE id::text = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'Learning Request not found.'; END IF;
  IF r.deleted_at IS NOT NULL OR upper(coalesce(r.status,'')) = 'DELETED' THEN
    RETURN jsonb_build_object('success', true, 'already_deleted', true);
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.student_profiles sp
    WHERE sp.user_id = v_uid
      AND (sp.id::text = coalesce(r.student_id::text,'')
        OR sp.user_id::text = coalesce(r.student_id::text,'')
        OR sp.id::text = coalesce(r.student_member_id::text,'')
        OR sp.user_id::text = coalesce(r.student_member_id::text,''))
  ) INTO v_is_student;

  SELECT EXISTS (
    SELECT 1 FROM public.tutor_profiles tp
    WHERE tp.user_id = v_uid
      AND (tp.id::text = coalesce(r.tutor_id::text,'')
        OR tp.user_id::text = coalesce(r.tutor_id::text,'')
        OR tp.id::text = coalesce(r.tutor_member_id::text,'')
        OR tp.user_id::text = coalesce(r.tutor_member_id::text,''))
  ) INTO v_is_tutor;

  IF NOT (v_is_student OR v_is_tutor) THEN
    RAISE EXCEPTION 'You can remove only your own Learning Request.';
  END IF;

  v_status := upper(coalesce(r.status,''));
  v_admin_decision := coalesce(to_jsonb(r)->>'admin_decision', to_jsonb(r)->>'admin_status', '');

  IF v_status NOT IN ('CANCELLED','CANCELED','COMPLETED','SOLVED','APPROVED','ADMIN_APPROVED',
                      'EXPIRED','REJECTED','REJECTED_BY_ADMIN','ADMIN_DENIED','RETURNED_TO_STUDENT') THEN
    RAISE EXCEPTION 'Only an old, closed Learning Request can be removed. Cancel an eligible active connection first.';
  END IF;

  IF v_status IN ('COMPLETED','SOLVED','APPROVED') AND nullif(btrim(v_admin_decision),'') IS NULL
     AND v_status <> 'ADMIN_APPROVED' THEN
    RAISE EXCEPTION 'Admin must finish the final review before this completed request can be removed.';
  END IF;

  IF v_status LIKE '%DISPUT%' OR v_status LIKE '%REVIEW%' OR v_status LIKE '%PENDING_ADMIN%'
     OR (upper(coalesce(to_jsonb(r)->>'student_outcome','')) = 'NOT_SATISFIED'
         AND nullif(btrim(v_admin_decision),'') IS NULL) THEN
    RAISE EXCEPTION 'Admin must resolve the dispute before this request can be removed.';
  END IF;

  UPDATE public.gc_learning_requests
  SET status = 'DELETED', deleted_at = now(), deleted_by = v_uid
  WHERE id::text = p_request_id;

  RETURN jsonb_build_object('success', true, 'removed_from_dashboard', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public.gc_delete_learning_request_connection(p_connection_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  c public.gc_learning_request_connections%ROWTYPE;
  v_status text;
  v_request_status text := '';
  v_is_student boolean := false;
  v_is_tutor boolean := false;
  v_request jsonb := '{}'::jsonb;
  v_admin_decision text := '';
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Please log in again.'; END IF;

  SELECT * INTO c
  FROM public.gc_learning_request_connections
  WHERE id = p_connection_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'Connection Request not found.'; END IF;
  IF c.deleted_at IS NOT NULL THEN
    RETURN jsonb_build_object('success', true, 'already_deleted', true);
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.student_profiles sp
    WHERE sp.user_id = v_uid
      AND (sp.id::text = coalesce(c.student_id::text,'') OR sp.user_id::text = coalesce(c.student_id::text,''))
  ) INTO v_is_student;
  SELECT EXISTS (
    SELECT 1 FROM public.tutor_profiles tp
    WHERE tp.user_id = v_uid
      AND (tp.id::text = coalesce(c.tutor_id::text,'') OR tp.user_id::text = coalesce(c.tutor_id::text,''))
  ) INTO v_is_tutor;

  IF NOT (v_is_student OR v_is_tutor) THEN
    RAISE EXCEPTION 'You can remove only your own Connection Request.';
  END IF;

  SELECT to_jsonb(lr), upper(coalesce(lr.status,''))
    INTO v_request, v_request_status
  FROM public.gc_learning_requests lr
  WHERE lr.id::text = c.request_id::text
  LIMIT 1;
  v_admin_decision := coalesce(v_request->>'admin_decision', v_request->>'admin_status', '');

  IF upper(coalesce(c.status,'')) IN ('ACCEPTED','APPROVED','CONNECTED','TUTOR_ACCEPTED','IN_PROGRESS','PENDING_STUDENT','PENDING_TUTOR','PENDING','REQUESTED')
     AND v_request_status NOT IN ('CANCELLED','CANCELED','ADMIN_APPROVED','ADMIN_DENIED','REJECTED_BY_ADMIN','RETURNED_TO_STUDENT','DELETED')
     AND NOT (v_request_status IN ('COMPLETED','SOLVED','APPROVED') AND nullif(btrim(v_admin_decision),'') IS NOT NULL) THEN
    RAISE EXCEPTION 'An active connection cannot be removed. Use the existing Cancel process first.';
  END IF;

  IF v_request_status LIKE '%DISPUT%' OR v_request_status LIKE '%REVIEW%' OR v_request_status LIKE '%PENDING_ADMIN%'
     OR (upper(coalesce(v_request->>'student_outcome','')) = 'NOT_SATISFIED' AND nullif(btrim(v_admin_decision),'') IS NULL) THEN
    RAISE EXCEPTION 'Admin must resolve the dispute before this connection can be removed.';
  END IF;

  UPDATE public.gc_learning_request_connections
  SET deleted_at = now(), deleted_by = v_uid
  WHERE id = p_connection_id;

  RETURN jsonb_build_object('success', true, 'removed_from_dashboard', true);
END;
$function$;

REVOKE ALL ON FUNCTION public.gc_delete_learning_request_record(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.gc_delete_learning_request_connection(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gc_delete_learning_request_record(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.gc_delete_learning_request_connection(uuid) TO authenticated;
