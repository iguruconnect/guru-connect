GURU CONNECT — FULL ADMIN + ADVERTISEMENT REPAIR

This build uses the full GURU CONNECT Admin Dashboard baseline from the previous complete build. It restores the Admin workspace instead of replacing it with a reduced admin page.

ADMIN DASHBOARD RESTORED:
- Tutor & UTR Queue
- Student Directory
- Student/Tutor profile editing with Supabase sync
- Admin Create User Account
- Find User / Password Reset
- Coin History / accountability ledger
- Learning Request records
- Learning Request + Coin Approval / Transfer / Deny
- Existing admin workflow and profile controls
- Admin Delete User (requires SUPABASE_ADMIN_DELETE_USER.sql once)

ADVERTISEMENT SYSTEM:
- 📢 ADVERTISEMENTS tab inside Staff/Admin Dashboard
- Create advertisement
- Upload flyer
- Placement dropdown: LRR | Student Profile | Tutor Profile | All Sections
- Start/end dates
- Priority
- Optional website / WhatsApp click-through
- Activate / Pause / Delete
- Dedicated advertisements.html manager
- Active ads automatically appear in the LRR and Student/Tutor profile grids

FLYER SIZES:
- Student/Tutor profile cards: 1000 × 1500 px portrait (2:3)
- LRR cards: 1000 × 1200 px portrait (5:6)
- JPG, JPEG, PNG, WEBP
- Maximum 5 MB

SUPABASE SQL:
1. If the advertisement setup has NOT already been run, run SUPABASE_ADVERTISEMENTS_SETUP.sql once.
2. Run SUPABASE_ADMIN_DELETE_USER.sql once if you want the Admin Delete User button to permanently remove the linked Student/Tutor Auth account.
3. If the advertisement SQL already returned “Success — no rows returned”, do not rerun it unnecessarily.
