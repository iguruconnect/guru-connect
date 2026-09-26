GURU CONNECT — OTP REGISTRATION + BRANDED EMAIL FIX
======================================================

WHAT THIS PACKAGE FIXES
-----------------------
1. Student and Tutor homepage registration now uses ONE real Supabase email OTP
   verification flow instead of mixing:
   - Supabase confirmation emails
   - a separate 4-digit EmailJS OTP
   This was causing the registration/verification experience to be inconsistent.

2. The homepage registration OTP is now a 6-digit OTP and is verified with:
      supabase.auth.verifyOtp({ email, token, type: 'email' })

3. A large GURU CONNECT branded popup appears immediately after an OTP is sent.
   It tells the user:
      "OTP Sent Successfully"
      "Your 6-digit verification OTP has been sent to: [email]"
      "Please check your Inbox. If you do not see it, check your Junk / Spam folder."

4. The standalone registration.html OTP was also corrected from 8 digits to 6
   digits and receives the same large branded "OTP Sent Successfully" popup.

5. The homepage profile-save function now tries the included secure
   gc_register_verified_profile() RPC first. It falls back to the older
   gc_register_member() RPC if that older function already exists in the
   Supabase project.

6. The supplied "Email Header 2.png" artwork has been added as:
      guru-connect-email-header-otp.png

8. The OTP email layout has been updated so the artwork is displayed FULLY
   untouched. The dynamic OTP and Inbox/Junk/Spam message are now in a clean
   card BELOW the artwork. Nothing is placed over the logo, people, headline,
   phone number or other brand elements.

7. A ready-to-paste Supabase HTML email template is included:
      SUPABASE_GURU_CONNECT_OTP_EMAIL_TEMPLATE.html

IMPORTANT SUPABASE STEP — DO THIS ONCE
--------------------------------------
The website ZIP cannot directly change the hosted Supabase Auth email template.
You must paste the included template into your Supabase Dashboard.

1. Open Supabase Dashboard.
2. Open your GURU CONNECT project.
3. Go to Authentication → Email Templates.
4. Open the authentication email template used for signup/email verification
   ("Confirm signup" in the hosted dashboard).
5. Replace its HTML with the contents of:
      SUPABASE_GURU_CONNECT_OTP_EMAIL_TEMPLATE.html
6. Save the template.

The template uses:
      {{ .Email }}
      {{ .Token }}
      {{ .SiteURL }}

Supabase's current email-template documentation supports {{ .Token }} for the
OTP. The GURU CONNECT website now expects the current 6-digit email OTP.

IMAGE HOSTING
-------------
The email template references:
      https://www.guruconnnect.in/guru-connect-email-header-otp.png

The new image is included in this ZIP. After the website is deployed, confirm
that this image URL opens directly in a browser. If your live site uses another
domain, change the image URL in the Supabase email template to that exact
public image URL.

REGISTRATION PROFILE SQL
------------------------
For the secure profile-save RPC used by this package, run once:

      SUPABASE_REGISTRATION_PROFILE_FIX_2026-09-24.sql

If you have already run that SQL successfully, do not run it repeatedly just
because the ZIP was updated.

RECOMMENDED TEST
----------------
1. Use a NEW email address that has never completed GURU CONNECT registration.
2. Open Student Registration.
3. Enter email + password.
4. Click SEND EMAIL OTP.
5. Confirm the large GURU CONNECT popup appears.
6. Check Inbox and Junk/Spam.
7. Enter the 6-digit OTP in the popup.
8. Complete the rest of the registration fields.
9. Submit the registration.
10. Confirm the Student profile appears in Supabase.
11. Repeat with a new Tutor email.

IMPORTANT
---------
The ZIP cannot edit the hosted Supabase email template by itself. The included
HTML template and image are ready; the one-time Dashboard paste/save step is
required for the branded email itself.

Do not disable email confirmations just to bypass the OTP. The registration
flow is designed around verified email accounts.
