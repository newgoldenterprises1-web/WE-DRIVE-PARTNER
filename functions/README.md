# WE DRIVE Partner payment backend

This directory is reserved for the Firebase Functions payment backend.

Required production setup:
- Node.js 22 runtime.
- Official Razorpay Node SDK.
- Razorpay Key ID and Key Secret stored in Firebase Secret Manager.
- Server-created Razorpay orders for ₹299 onboarding and ₹699 Premium Drive.
- Server-side HMAC signature verification and captured-payment verification before updating `/partners/{uid}`.

The Flutter app includes the Razorpay checkout dependency, but account activation must remain server-controlled.

Suggested deployment flow:
1. Configure Razorpay test credentials in Firebase Secret Manager.
2. Deploy the payment functions.
3. Run test payments and verify captured status.
4. Switch to live credentials only after successful end-to-end tests.
5. Deploy the production functions again.
