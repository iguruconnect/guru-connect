-- GURU CONNECT student Helpline registration payment metadata
-- Safe additive migration: does not update or rewrite existing student records.
-- Run this script in Supabase SQL Editor before using the updated registration form.

ALTER TABLE public.student_profiles
  ADD COLUMN IF NOT EXISTS helpline_service_choice text,
  ADD COLUMN IF NOT EXISTS helpline_payment_mode text,
  ADD COLUMN IF NOT EXISTS helpline_payment_reference text,
  ADD COLUMN IF NOT EXISTS helpline_paid_to_type text,
  ADD COLUMN IF NOT EXISTS helpline_paid_to_name text,
  ADD COLUMN IF NOT EXISTS helpline_branch_name text,
  ADD COLUMN IF NOT EXISTS helpline_paid_to_registration_no text,
  ADD COLUMN IF NOT EXISTS helpline_receipt_number text,
  ADD COLUMN IF NOT EXISTS helpline_payment_status text;

COMMENT ON COLUMN public.student_profiles.helpline_service_choice IS
  'Whether a student registered with or without the optional Helpline Service.';
COMMENT ON COLUMN public.student_profiles.helpline_payment_mode IS
  'Student Helpline payment mode reported at registration: upi or cash.';
COMMENT ON COLUMN public.student_profiles.helpline_payment_reference IS
  'UPI UTR / transaction reference reported by the student.';
COMMENT ON COLUMN public.student_profiles.helpline_paid_to_type IS
  'Cash recipient category reported by the student.';
COMMENT ON COLUMN public.student_profiles.helpline_paid_to_name IS
  'Name of the cash recipient when paid to a Business Development Executive or GC Authorized Person.';
COMMENT ON COLUMN public.student_profiles.helpline_branch_name IS
  'GURU CONNECT branch name when cash was paid at a branch.';
COMMENT ON COLUMN public.student_profiles.helpline_paid_to_registration_no IS
  'Registration number of the cash recipient when applicable.';
COMMENT ON COLUMN public.student_profiles.helpline_receipt_number IS
  'Receipt number provided for a cash Helpline payment.';
COMMENT ON COLUMN public.student_profiles.helpline_payment_status IS
  'Registration-reported payment status; not proof of payment verification.';
