GURU CONNECT — EXISTING EMAIL OTP FIX
========================================

WHAT CHANGED
------------
registration.html no longer uses auth.signUp() to request the verification code.

It now uses:
  supabase.auth.signInWithOtp({
    email,
    options: {
      shouldCreateUser: true,
      data: metadata
    }
  })

This is important because signUp() is not the correct "send a fresh OTP to an
already-existing email" mechanism. The new flow sends an OTP to the current
owner of the email whether the Auth identity already exists or must be created.

AFTER OTP VERIFICATION
----------------------
The verified Auth session is reused for the existing registration profile flow.
The password entered on the registration form is applied to the verified
account so normal GURU CONNECT password login continues to work.

A safety check also prevents an existing Student account from accidentally
being converted to Tutor (or vice versa) by this page.

IMPORTANT SUPABASE EMAIL TEMPLATE STEP
--------------------------------------
signInWithOtp() uses the Supabase "Magic Link" authentication email template.

Therefore, in:
  Supabase Dashboard
  -> Authentication
  -> Email Templates

make sure the "Magic Link" template also contains the 8-digit OTP using:

  {{ .Token }}

Use the supplied:
  SUPABASE_GURU_CONNECT_OTP_EMAIL_TEMPLATE.html

You can use the same GURU CONNECT OTP HTML for the Magic Link template if the
template editor accepts it. Keep the {{ .Email }}, {{ .Token }} and {{ .SiteURL }}
variables intact.

Also keep the same OTP template in "Confirm signup" if you want the same
branded email for any confirmation-signup path elsewhere on the website.

NO DATABASE CLEANUP
-------------------
Do NOT delete the anonymous Auth users.
Do NOT change auth.users token columns.
Do NOT disable gc_sync_auth_member().
Do NOT delete existing Tutor/Student profiles.

The registration/profile-save RPC already present in this package remains in
place.

IMPORTANT ROLE NOTE
-------------------
The current GURU CONNECT data model has one canonical public.profiles.role per
Auth user. If an existing verified account is already a Tutor and someone tries
to register that same email as Student, this page stops rather than silently
changing the existing account's role. This protects existing member data.
