GURU CONNECT — TUTOR PAYMENT RECEIPT FEATURE
================================================

Updated: 2026-09-24

WHAT WAS ADDED
- Admin search results show a GENERATE RECEIPT button for Tutor accounts only.
- Receipt modal with tutor/payment details.
- Payment purpose options:
  Tutor Listing, Verified Tick, Tutor Listing + Verified Tick, Renewal, Other.
- Amount, currency, payment date, payment status, payment method and UTR/Transaction ID fields.
- Professional GURU CONNECT receipt preview.
- GURU CONNECT logo and slogan: "connecting minds creating future".
- Contact details:
  support@guruconnnect.in
  WhatsApp: +1 (555) 9565 - 917
- Receipt footer clearly states:
  "AUTO-GENERATED RECEIPT — SIGNATURE NOT REQUIRED"
- DOWNLOAD PDF uses jsPDF loaded from jsDelivr.
- PRINT / SAVE PDF is also available.
- Receipt number is generated automatically in the format GC-REC-YYYYMMDD-HHMMSS.

HOW TO USE
1. Open the Staff/Admin dashboard.
2. Search for a Tutor.
3. Click GENERATE RECEIPT.
4. Enter the amount and payment details.
5. Click UPDATE PREVIEW to review.
6. Click DOWNLOAD PDF.

NOTE
The receipt feature is client-side in admin.html. It does not expose a Supabase service-role key and does not alter the existing admin-user-actions Edge Function.
