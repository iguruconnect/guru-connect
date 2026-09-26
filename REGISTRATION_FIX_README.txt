GURU CONNECT — REGISTRATION FIX

The registration page has been changed so it no longer uses the failing
client-side ON CONFLICT upserts for the canonical profile save.

ONE-TIME SUPABASE STEP:
1. Open Supabase Dashboard -> SQL Editor.
2. Open and run: SUPABASE_REGISTRATION_PROFILE_FIX_2026-09-24.sql
3. Wait about 10-20 seconds.
4. Refresh registration.html and test a new Student registration and a new Tutor registration.

The SQL installs public.gc_register_verified_profile(), which updates an existing
profile row or inserts a new one. It is scoped to the authenticated user's own
UUID and avoids dependence on the PostgREST onConflict target for registration.

Do not delete existing users or profiles to apply this fix.


UPDATED OTP FLOW (2026-09-26)
-----------------------------
The homepage Student/Tutor registration now uses Supabase's real email OTP
verification and expects the current 6-digit token. The old registration-time
4-digit EmailJS OTP is no longer used by the homepage registration submit flow.

A large branded "OTP Sent Successfully" popup tells the user to check Inbox and
Junk/Spam. The standalone registration.html has the same 6-digit behavior.

For the live branded email itself, paste:
  SUPABASE_GURU_CONNECT_OTP_EMAIL_TEMPLATE.html
into Supabase Dashboard -> Authentication -> Email Templates -> Confirm signup.

The supplied image is:
  guru-connect-email-header-otp.png

The preferred profile-save RPC is:
  public.gc_register_verified_profile(uuid,text,jsonb)

Run:
  SUPABASE_REGISTRATION_PROFILE_FIX_2026-09-24.sql
once in Supabase SQL Editor if that function is not already installed.
