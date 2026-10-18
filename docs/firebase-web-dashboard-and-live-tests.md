# Firebase setup, live sync, web dashboard and end-to-end verification

## Important security model
The app sync path is `users/{Firebase UID}/{table}/{record ID}`. `firestore.rules` allows an authenticated user to access only their own UID namespace and only the allow-listed collection names. Rules are a hard boundary; UI filtering is not a security control.

Before deploying these rules, verify every collection used by `SyncQueueService` is listed. New synced collections must be added to the allow-list and reviewed.

## Configure Firebase client values
Client Firebase config is not a service-account secret, but values must match the registered Firebase apps. Do not commit service-account JSON or Admin SDK private keys.

Example Android build:
```powershell
flutter build apk --release --dart-define=FIREBASE_PROJECT_ID=shopkeeper-2de9a --dart-define=FIREBASE_ANDROID_API_KEY=YOUR_REAL_ANDROID_API_KEY --dart-define=FIREBASE_ANDROID_APP_ID=YOUR_REAL_ANDROID_APP_ID --dart-define=FIREBASE_MESSAGING_SENDER_ID=YOUR_REAL_SENDER_ID --dart-define=FIREBASE_STORAGE_BUCKET=shopkeeper-2de9a.appspot.com
```

Example web build (replace values with the Web App config from Firebase Console → Project settings → Your apps):
```powershell
flutter build web --release --target=lib/web_main.dart --dart-define=FIREBASE_PROJECT_ID=shopkeeper-2de9a --dart-define=FIREBASE_WEB_API_KEY=YOUR_REAL_WEB_API_KEY --dart-define=FIREBASE_WEB_APP_ID=YOUR_REAL_WEB_APP_ID --dart-define=FIREBASE_MESSAGING_SENDER_ID=YOUR_REAL_SENDER_ID --dart-define=FIREBASE_AUTH_DOMAIN=shopkeeper-2de9a.firebaseapp.com --dart-define=FIREBASE_STORAGE_BUCKET=shopkeeper-2de9a.appspot.com
```

Do not deploy a web build until all values are present and Firebase Phone Auth's authorized domains include the hosting domain. The repository does not contain real Firebase app identifiers, so a working production build cannot be produced from placeholders alone. The web target is separate from the mobile entry point so it does not initialize SQLite in the browser.

## Hosting
`firebase.json` configures Firestore rules, Flutter web hosting from `build/web`, SPA rewrites, security headers and local Auth/Firestore emulators.

```powershell
npm install -g firebase-tools
firebase login
firebase use shopkeeper-2de9a
flutter build web --release <the --dart-define values above>
firebase deploy --only firestore:rules,hosting
```

Review the project and rules in the Firebase Console before deploying. Enable Email/Password under Firebase Authentication for the web dashboard. The cargo tracking endpoint is deployed as a Cloud Function and may require the Firebase project to be on the Blaze billing plan; set billing alerts and review estimated costs before deployment. Hosting is not considered complete until the deployed HTTPS URL and /api/track endpoint are tested.

## Emulator setup and security tests
Install test-only packages in a separate test workspace:
```powershell
npm install --save-dev @firebase/rules-unit-testing firebase
firebase emulators:start --only auth,firestore
```
Create test accounts A and B in the Auth emulator. Test authenticated A can read/write `users/A/products/p1`; A is denied access to `users/B/products/p1`; B is denied access to A; unauthenticated access is denied. Keep emulator tests separate from physical-device tests.

## Live two-account/two-device test record
Use two real test accounts and two devices. Test online create/update, offline queued changes, restart, reconnect, account switching, logout/cache isolation, Firestore rule denials, and duplicate/conflicting updates. Record the commit SHA and screenshots/logs. Unit tests and emulator tests do not replace this real-device check.

## Restaurant acceptance tests
Create menu item and table, place order, add multiple lines, verify calculated total, move items through kitchen statuses, record full/split payment, reject mismatched or duplicate payment, complete only after paid and served/cancelled, verify table release, bill/receipt and sales/finance report after app restart.

## Vehicle and cargo acceptance tests
Vehicle purchases/sales must reconcile with cash/expense/income records and profit reports, not only vehicle status. Cargo history must be timestamped and customer-visible tracking must use an unguessable scoped token; never expose all cargo data through unauthenticated list queries.

## Vertical-module acceptance tests
School, clinic, salon, agriculture, construction and public-service modules each need create/update/status lifecycle, payments/expenses, validation, branch scoping and reports. Clinic data needs strict access controls. Do not mark a module complete until a workflow is tested end to end.

## Release gate
A successful CI build, emulator tests, live device test record, verified Firestore rules, deployed dashboard URL, account isolation, backup/restore and receipt/printing tests are required before calling the app production-ready.
