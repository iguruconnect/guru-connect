-- GURU CONNECT: compatibility wrappers for legacy Learning Request posting RPCs
-- Route legacy calls through auth.uid()-based canonical posting.
-- Does not transfer coins or alter existing Learning Requests.
-- gc_learning_requests_v2 is a VIEW; canonical posting writes to the base table.
-- Preserve the original return types: UUID overload JSONB, text overload TEXT.

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
    p_course, p_stream, p_subject, p_topic, 'Online', p_problem
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
RETURNS text
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT public.gc_post_my_learning_request(
    p_course, p_stream, p_subject, p_topic, 'Online', p_problem
  )::text;
$function$;

COMMIT;

-- Read-only verification after deployment:
-- SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS arguments,
--        pg_get_function_result(p.oid) AS result
-- FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
-- WHERE n.nspname = 'public'
--   AND p.proname IN ('gc_post_learning_request','gc_post_my_learning_request')
-- ORDER BY p.proname, arguments;
--
-- This wrapper migration alone does not complete the full single-ID migration.
