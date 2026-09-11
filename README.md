# WE DRIVE Partner

Production-focused Flutter partner/driver app for WE DRIVE.

## Included

- Splash, login and signup
- Firebase Authentication / Firestore partner profile
- Home dashboard with online/offline presence
- Live booking requests and booking assignment
- Booking lifecycle: accept, arriving, arrived, start trip, complete trip
- Google Maps driving navigation
- Device location permission and foreground location updates
- Pre-trip vehicle inspection photos and driver selfie
- Post-trip inspection photos
- Firebase Storage inspection uploads with booking-scoped paths
- Earnings and completed-trip analytics
- Account, profile, verification, journey history, notifications, support and logout screens

## Firebase

The app is configured for the WE DRIVE Partner Firebase project in `firebase_options.dart`.
Firestore and Storage rules are version-controlled in:

- `firestore.rules`
- `storage.rules`

Deploy rules from a machine with the Firebase CLI authenticated to the project:

```bash
firebase deploy --only firestore:rules,storage
```

## Dependencies

The project uses third-party Flutter packages for Firebase, navigation, geolocation, image capture and related platform functionality. Run:

```bash
flutter clean
flutter pub get
flutter analyze
flutter run -d <device>
```

## Android release signing

Release signing is environment/config driven. Do not commit the real keystore or `android/key.properties`.

Copy:

```text
android/key.properties.example
```

to:

```text
android/key.properties
```

and fill in your private keystore values before creating a release build.

## Verification status

The repository is hardened for production workflows, but final device-level validation still requires a local Flutter SDK, Firebase project access and a real Android/iOS device or emulator. A successful Git commit is not proof that an APK/AAB or all runtime flows have been tested.
