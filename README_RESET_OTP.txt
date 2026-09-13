GURU CONNECT FINAL OTP PASSWORD RESET PACKAGE

1. Upload/replace the root website files: index.html, dashboard.html, learning.html, reset-otp.html, reset-password.html.
2. Upload guru-connect-logo.png and guru-connect-email-hero.jpg to the SAME website root (GitHub Pages root).
3. Supabase Auth -> Email Templates -> Reset Password: paste the HTML from SUPABASE_RECOVERY_EMAIL_OTP_TEMPLATE.html. Keep {{ .Token }} exactly as shown.
4. Supabase Auth -> URL Configuration -> Redirect URLs: add
   https://guruconnnect.in/reset-otp.html
   https://www.guruconnnect.in/reset-otp.html
   https://guruconnnect.in/reset-password.html
   https://www.guruconnnect.in/reset-password.html
5. User flow: MENU -> LOGIN (only one login item) -> choose Student/Tutor/Staff/Admin -> Forgot password? Send OTP -> open reset-otp.html -> enter email + OTP -> VERIFY OTP & CONTINUE -> create NEW password.
6. OTP is NEVER entered in the password field.
7. Test with one fresh reset request only. Use the newest OTP email.
