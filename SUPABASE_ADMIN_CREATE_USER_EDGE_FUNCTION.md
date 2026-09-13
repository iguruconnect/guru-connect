# GURU CONNECT — Admin Create User Edge Function

The Admin Dashboard's CREATE USER ACCOUNT button calls:

`https://hzqqswrnawrfgufbxgay.supabase.co/functions/v1/admin-create-user`

The previous website package did not contain a deployed function at that URL, which caused **Failed to fetch**.

## One-time Supabase setup

1. Open Supabase Dashboard for the GURU CONNECT project.
2. Go to **Edge Functions**.
3. Create a function named exactly:
   `admin-create-user`
4. Replace its default code with:
   `supabase/functions/admin-create-user/index.ts` from this package.
5. Deploy the function.
6. Supabase provides `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` to Edge Functions automatically. Do NOT put the service-role key into `index.html`.
7. The website is already configured to call the deployed function URL.

The function accepts requests only from the authorized Staff Admin account `swami@gmail.com` and creates either a Student or Tutor Auth account plus the corresponding public profile row.

## Password reset page

The public reset page is:
`https://guruconnnect.in/reset-password.html`

It is included in this package. It is a normal page where the user enters:
- registered email
- OTP from the newest reset email

After OTP verification, the page reveals:
- New Password
- Confirm New Password

The OTP is never used as the password.

After uploading the package to GitHub Pages, make sure `reset-password.html`, `guru-connect-logo.png`, and `guru-connect-email-hero.jpg` are in the same root folder as `index.html`.
