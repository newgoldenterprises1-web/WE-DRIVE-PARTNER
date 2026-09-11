WE DRIVE PARTNER — PREMIUM BOOKING FRONTEND UPDATE

Use this update on the CURRENT WORKING project. Do NOT replace android/.
Do NOT create a new project/folder.

1. Keep your current C:\Flutter Projects\we_drive_partner project.
2. Backup the current lib folder if desired.
3. Replace the existing project lib folder with this package's lib folder.
4. In the same current project terminal run:
   flutter clean
   flutter pub get
   flutter analyze
5. If analyze is clean, run:
   flutter run -d ZD222MXNJQ

Added:
- Dedicated Premium Bookings screen.
- Dedicated Premium Booking Detail screen.
- Premium eligibility gate via AppData.isPremiumPartner.
- Premium UI hidden from standard partners when the entitlement is false.
- Premium entry appears on Home and Account only for eligible partners.
- Immediate / Reservation / Completed premium tabs.
- Premium booking status flow: REQUESTED -> ACCEPTED -> ARRIVING -> ARRIVED -> TRIP_STARTED -> COMPLETED.
- No permanent customer vehicle field on premium booking card/detail.
- WE DRIVE navy/gold visual language retained.

Demo:
AppData.isPremiumPartner = true means this demo partner is treated as Premium.
For a Standard demo partner, set it to false. In production this must come from authorized backend/Firebase data, not a client-controlled flag.
