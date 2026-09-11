# WE DRIVE Partner — Clean Final Master

This master is intentionally rebuilt from clean, readable Dart files.

- No third-party packages.
- Modular screen folders.
- Splash
- Login
- Signup
- OTP demo (123456)
- Home dashboard
- Online / Offline (green / red)
- Bookings
- Booking details
- Accept / Reject
- Arriving / Arrived / Start Trip / Complete Trip
- Navigate / Contact demo actions
- Earnings
- Account
- Profile
- Verification
- Journey History
- Notifications
- Support
- Logout

Run:
flutter clean
flutter pub get
flutter analyze
flutter run -d <device>


## Android build fix
This master uses Flutter's standard plugin-loader includeBuild configuration.
On a fresh folder, run `flutter create .` once only if Flutter reports missing platform/wrapper files.
Then run:
flutter clean
flutter pub get
flutter analyze
flutter run -d <device>
