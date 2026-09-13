GURU CONNECT FINAL FIXES

1. Password reset is now ONE page: reset-password.html
   - User opens it from the email button.
   - Enters registered email + OTP.
   - OTP is verified.
   - Same page then shows NEW PASSWORD + CONFIRM PASSWORD.
   - OTP is never treated as the password.
2. reset-otp.html is kept as a compatibility redirect to reset-password.html.
3. All password-reset requests from index.html point to reset-password.html.
4. Menu contains one working Login area with Student, Tutor and Staff/Admin Login buttons.
5. Original GURU CONNECT logo is included as guru-connect-logo.png.
6. Branded email template is included. Paste the template HTML into Supabase Auth > Email Templates > Reset Password.
7. Email button points to: https://guruconnnect.in/reset-password.html
8. The email template uses {{ .Token }} for the OTP.
