WE DRIVE PARTNER — FINAL PREMIUM FRONTEND UPDATE

Replace ONLY the existing project's lib/ folder with this package.
Do NOT replace android/ or pubspec.yaml; the current Android project is already running.

Included:
- Premium Bookings separate screen
- Premium visibility gated by AppData.premiumFeatureVisible
- Immediate / Reservation / Completed tabs
- REQUESTED -> ACCEPTED -> ARRIVING -> ARRIVED -> TRIP_STARTED -> COMPLETED
- No permanent customer-vehicle field rendered in premium booking UI
- WE DRIVE navy/gold UI
- Existing standard booking, home, earnings, account, profile, support, and notifications screens

Production note:
Premium eligibility must later be enforced by backend/Firebase rules. The demo flag is for frontend testing only.
