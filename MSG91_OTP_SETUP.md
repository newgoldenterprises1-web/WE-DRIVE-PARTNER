# WE DRIVE — MSG91 WhatsApp OTP Setup

The Partner app now uses MSG91 OTP for mobile verification. Firebase Phone OTP is not used. Firebase Auth remains only as the secure application session/database identity after MSG91 verification.

## 1. MSG91 widget

- Widget ID: `36696d6a754f383834373433`
- Mobile Integration: ON
- Country restriction: India
- WhatsApp is the primary channel configured in the widget.
- SMS retry/fallback uses channel `11`.
- WhatsApp retry uses channel `12`.

The Flutter SDK documents `sendOTP`, `retryOTP`, and `verifyOTP`, and supports WhatsApp through `WHATSAPP-12`. See the MSG91 SendOTP Flutter SDK documentation.

## 2. Flutter auth token

Do not hard-code the MSG91 widget auth token into source control. Build/run the app with:

```bash
flutter pub get
flutter run --dart-define=MSG91_AUTH_TOKEN=YOUR_WIDGET_AUTH_TOKEN
```

For a release build, pass the same dart define through the release build/CI secret.

## 3. Firebase backend secret

The server-side MSG91 Authkey must never be placed in Flutter code.

From the Firebase project directory, set the Cloud Secret Manager value:

```bash
firebase functions:secrets:set MSG91_AUTHKEY
```

Enter the MSG91 Authkey when prompted, then deploy:

```bash
firebase deploy --only functions
```

The deployed functions are:

- `verifyDriverMsg91AccessToken`
- `verifyCustomerMsg91AccessToken`

The functions verify the MSG91 access token server-side and then mint a Firebase custom token. The client signs in with `signInWithCustomToken()`.

## 4. Security model

MSG91 handles OTP generation and verification. Firebase does not generate or send the OTP.

Firebase is still used after successful OTP verification so Firestore/Storage security rules can continue to use `request.auth` and a stable Firebase UID.

Do not commit:

- MSG91 Authkey
- Firebase service-account private keys
- production secrets
- `.env` files containing secrets
