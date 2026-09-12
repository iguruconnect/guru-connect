# GURU CONNECT authentication update — 12 Sep 2026

## What was fixed in the website
- Student/Tutor login is **Email + Password only**.
- The old simulated login OTP/code path is disabled.
- Student and Tutor registration show Password + Confirm Password.
- Registration uses Supabase Auth and email verification.
- Forgot Password sends a Supabase recovery email.
- Recovery page lets the user create a new password.
- Login has a **NEW REGISTRATION** shortcut.
- Learning Requests is kept as one menu destination (`learning.html`); the legacy registration-section Learning Request tab is hidden.
- Admin Dashboard contains **CREATE USER ACCOUNT**.
- The Admin user creator creates a real Supabase Auth account and a linked Student/Tutor profile through the included server-side Edge Function.
- No service-role key or Staff password is embedded in the website.

## One-time Supabase deployment
The browser cannot safely create Auth users with the Supabase service-role key. Deploy the included Edge Function:

```bash
supabase functions deploy admin-create-user
```

The function uses the standard Supabase project environment variables:
- SUPABASE_URL
- SUPABASE_ANON_KEY
- SUPABASE_SERVICE_ROLE_KEY

These are server-side values; **do not put the service-role key in `index.html`.**

The website already points its Admin Create User button to:

`https://hzqqswrnawrfgufbxgay.supabase.co/functions/v1/admin-create-user`

After deployment, Admin can create Student/Tutor accounts directly from the Admin Dashboard.

## Important Staff security change
The previous source contained a Staff password in client-side JavaScript. That has been removed. Staff login now authenticates against Supabase using the password entered into the Staff login form.

## Password reset
In Supabase Authentication → URL Configuration, make sure the live recovery URL is allowed:

`https://www.guruconnnect.in/index.html?password_reset=1`

Also ensure Supabase email delivery/SMTP is configured.

## Login behavior
- Student: choose Student → email → password.
- Tutor: choose Tutor → email → password.
- A phone number alone can never log a Student/Tutor in.
- The old on-screen simulated code (`1234`) is disabled.

## Admin-created users
Admin enters:
- Full name
- Login email / username
- Optional phone
- Student or Tutor
- Password + confirmation

The created user can immediately log in with that email/password. They can later use Forgot Password.
