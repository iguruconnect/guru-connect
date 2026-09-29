GURU CONNECT — ADMIN + REGISTRATION/PASSWORD REPAIR
====================================================

This package repairs the following:

1. Staff/Admin can EDIT Student/Tutor profiles.
2. Staff/Admin can DELETE Student/Tutor accounts.
3. Staff/Admin can GRANT/REMOVE the Tutor VERIFIED tick.
4. Staff/Admin can MARK Tutor PAYMENT PAID/UNPAID.
5. These admin actions do NOT read, change, deduct, award, or depend on GURU COINS.
6. Staff/Admin can reset a Student/Tutor password from the Admin Control Center.
7. Registration no longer depends on upsert(... ON CONFLICT user_id). It uses a protected Supabase RPC after email verification.
8. Existing 8-digit email OTP registration flow is preserved.
9. Forgot-password / reset-password pages remain Supabase Auth based.

IMPORTANT — ONE SUPABASE STEP
--------------------------------
Run:
    SUPABASE_ADMIN_REGISTRATION_PASSWORD_REPAIR.sql
in Supabase Dashboard -> SQL Editor -> Run.

Then reload the website and login as:
    guruconnect.in@gmail.com

Admin page:
    admin.html

NOTES
-----
- Do NOT put a Supabase service-role key in HTML/JavaScript.
- The Create User button continues using the project's existing protected Edge Function.
- The repaired edit/delete/verified/payment/reset/search operations use protected SECURITY DEFINER RPCs.
- GURU Coins are intentionally not referenced by the new admin functions.
- If Supabase Auth password-reset emails do not arrive, verify the Supabase Auth SMTP/email settings and the allowed redirect URL. The website code cannot override those project-level settings.
