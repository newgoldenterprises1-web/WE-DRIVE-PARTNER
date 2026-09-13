# WE DRIVE external backend

This backend replaces the Firebase Cloud Functions layer so the WE DRIVE app does not require Firebase Cloud Functions billing.

## Required environment variables

- `MSG91_AUTHKEY` — the NEW rotated MSG91 server-side Authkey. Never put this in Flutter or GitHub source.
- `FIREBASE_SERVICE_ACCOUNT_JSON` — the Firebase Admin service-account JSON for project `we-drive-4315a`, stored as one JSON string in the hosting provider's secret/environment settings.
- `PORT` — supplied automatically by most hosts; local default is `8080`.

## Endpoints

- `GET /health`
- `POST /api/auth/driver/msg91`
- `POST /api/auth/customer/msg91`
- `POST /api/driver/presence` — Firebase ID token required.
- `POST /api/driver/location` — Firebase ID token + driver role required.
- `POST /api/bookings/:bookingId/accept` — Firebase ID token + driver role required.
- `POST /api/bookings/:bookingId/decline` — Firebase ID token + driver role required.

The backend verifies the MSG91 access token server-side, creates/gets the Firebase user, applies the role claim, and returns a Firebase custom token. The Flutter app then signs in with that custom token.

## Local run

```powershell
cd backend
npm install
$env:MSG91_AUTHKEY="YOUR_NEW_MSG91_AUTHKEY"
$env:FIREBASE_SERVICE_ACCOUNT_JSON='{"type":"service_account",...}'
npm start
```

Do not commit the real service-account JSON or Authkey.

## Render deployment

The repository includes `render.yaml`. Create a Node web service from this repository with `backend` as the root directory, then add the two secret environment variables above. After deployment, verify:

```text
https://YOUR-BACKEND-URL/health
```

The Flutter build must receive the backend URL as:

```powershell
flutter run --dart-define=MSG91_AUTH_TOKEN=YOUR_NEW_WIDGET_AUTH_TOKEN --dart-define=WE_DRIVE_API_BASE_URL=https://YOUR-BACKEND-URL
```

The widget Auth Token is a client-side integration token, but it should still not be committed to source. The MSG91 Authkey is server-only.
