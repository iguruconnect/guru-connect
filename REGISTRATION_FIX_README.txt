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
