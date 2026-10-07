-- GURU CONNECT — WhatsApp Phone Number Lookup Fix
-- Run this in Supabase SQL Editor
-- Fixes: "column phone does not exist" and phone lookup failures

BEGIN;

-- ============================================================
-- 1. Create the WhatsApp contact lookup RPC (most reliable)
-- ============================================================
CREATE OR REPLACE FUNCTION public.gc_get_whatsapp_contact(
  p_request_id UUID,
  p_target_role TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $func1$
DECLARE
  v_tutor_id UUID;
  v_student_id UUID;
  v_target_id UUID;
  v_target_table TEXT;
  v_phone TEXT;
  v_name TEXT;
BEGIN
  SELECT student_id, tutor_id 
  INTO v_student_id, v_tutor_id
  FROM public.gc_learning_requests_v2
  WHERE id = p_request_id
  LIMIT 1;

  IF v_tutor_id IS NULL OR v_student_id IS NULL THEN
    RAISE EXCEPTION 'Learning Request not found or missing participants';
  END IF;

  IF p_target_role = 'tutor' THEN
    v_target_id := v_tutor_id;
    v_target_table := 'tutor_profiles';
  ELSE
    v_target_id := v_student_id;
    v_target_table := 'student_profiles';
  END IF;

  EXECUTE 'SELECT phone, name FROM public.' || v_target_table || ' WHERE id = $1 OR user_id = $1 LIMIT 1'
  INTO v_phone, v_name
  USING v_target_id;

  IF v_phone IS NULL THEN
    SELECT phone, full_name
    INTO v_phone, v_name
    FROM public.profiles
    WHERE id = v_target_id
    LIMIT 1;
  END IF;

  IF v_phone IS NULL THEN
    EXECUTE 'SELECT phone, name FROM public.' || v_target_table || ' WHERE user_id = $1 LIMIT 1'
    INTO v_phone, v_name
    USING v_target_id;
  END IF;

  RETURN jsonb_build_object(
    'phone', COALESCE(v_phone, ''),
    'name', COALESCE(v_name, ''),
    'found', v_phone IS NOT NULL
  );
END;
$func1$;

REVOKE ALL ON FUNCTION public.gc_get_whatsapp_contact(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gc_get_whatsapp_contact(UUID, TEXT) TO authenticated;

-- ============================================================
-- 2. Create helper function to normalize WhatsApp numbers
-- ============================================================
CREATE OR REPLACE FUNCTION public.gc_normalize_whatsapp_number(p_raw_phone TEXT)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
AS $func2$
DECLARE
  v_digits TEXT;
BEGIN
  v_digits := regexp_replace(p_raw_phone, '[^0-9]', '', 'g');
  
  IF v_digits = '' THEN
    RETURN '';
  END IF;

  IF v_digits LIKE '00%' THEN
    v_digits := substring(v_digits, 3);
  END IF;

  IF length(v_digits) = 11 AND v_digits LIKE '0%' THEN
    v_digits := substring(v_digits, 2);
  END IF;

  IF length(v_digits) = 10 THEN
    v_digits := '91' || v_digits;
  END IF;

  IF v_digits ~ '^[1-9][0-9]{10,14}$' THEN
    RETURN v_digits;
  END IF;

  RETURN COALESCE(v_digits, '');
END;
$func2$;

REVOKE ALL ON FUNCTION public.gc_normalize_whatsapp_number(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gc_normalize_whatsapp_number(TEXT) TO authenticated;

-- ============================================================
-- 3. Direct lookup function for debugging
-- ============================================================
CREATE OR REPLACE FUNCTION public.gc_debug_whatsapp_lookup(p_profile_id UUID)
RETURNS TABLE(
  id UUID,
  name TEXT,
  phone TEXT,
  source TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $func3$
BEGIN
  RETURN QUERY
  SELECT 
    tp.id,
    tp.name,
    tp.phone,
    'tutor_profiles'::TEXT
  FROM public.tutor_profiles tp
  WHERE tp.id = p_profile_id OR tp.user_id = p_profile_id
  LIMIT 1;

  RETURN QUERY
  SELECT 
    sp.id,
    sp.name,
    sp.phone,
    'student_profiles'::TEXT
  FROM public.student_profiles sp
  WHERE sp.id = p_profile_id OR sp.user_id = p_profile_id
  LIMIT 1;

  RETURN QUERY
  SELECT 
    p.id,
    p.full_name,
    p.phone,
    'profiles'::TEXT
  FROM public.profiles p
  WHERE p.id = p_profile_id
  LIMIT 1;
END;
$func3$;

REVOKE ALL ON FUNCTION public.gc_debug_whatsapp_lookup(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.gc_debug_whatsapp_lookup(UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;
