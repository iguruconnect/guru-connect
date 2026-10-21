-- GURU CONNECT: compatibility wrappers for legacy Learning Request posting RPCs
-- Purpose: keep older pages working while ensuring all new requests use auth.uid()
-- through gc_post_my_learning_request. This script does NOT move coins or alter
-- existing requests. Run in Supabase SQL Editor only after reviewing the function
-- signatures in the live project.
--
-- IMPORTANT: gc_learning_requests_v2 is a VIEW. These wrappers deliberately call
-- gc_post_my_learning_request, which writes to the base gc_learning_requests table.

BEGIN;

CREATE OR REPLACE FUNCTION public.gc_post_learning_request(
  p_course text,
  p_problem text,
  p_stream text,
  p_student_id uuid,
  p_subject text,
  p_topic text
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT public.gc_post_my_learning_request(
    p_course,
    p_stream,
    p_subject,
    p_topic,
    'Online',
    p_problem
  );
$function$;

CREATE OR REPLACE FUNCTION public.gc_post_learning_request(
  p_student_id text,
  p_course text,
  p_stream text,
  p_subject text,
  p_topic text,
  p_problem text
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT public.gc_post_my_learning_request(
    p_course,
    p_stream,
    p_subject,
    p_topic,
    'Online',
    p_problem
  );
$function$;

COMMIT;

-- Post-deployment verification (read-only):
-- SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS arguments,
--        pg_get_function_result(p.oid) AS result
-- FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
-- WHERE n.nspname = 'public'
--   AND p.proname IN ('gc_post_learning_request','gc_post_my_learning_request')
-- ORDER BY p.proname, arguments;
--
-- Do not treat this wrapper migration as completion of the full single-ID
-- migration. Connection, completion/outcome, notifications, and payout paths
-- still require separate verified alignment.
