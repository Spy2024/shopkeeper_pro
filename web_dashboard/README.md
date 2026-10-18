# Shopkeeper Pro Web Dashboard

This is a responsive, read-only owner dashboard for cloud data. It is a separate static web app and does not replace the Flutter Android app.

## Setup

1. In Firebase Console, open Project settings and register a **Web app** in the existing project.
2. Copy `firebase-config.example.js` to `firebase-config.js` and fill in the Web App configuration values.
3. Enable Phone authentication in Firebase Authentication; enable Email/Password too only if you intend to use email sign-in. Phone OTP is supported in the dashboard so it can use the same Firebase UID as the Android app. Email/password works only for accounts linked to the same UID.
4. Apply and test the user-scoped Firestore rules in `../firestore.rules.example` before deployment. Never use public read/write rules.
5. Serve this directory from a local static server or deploy it to an HTTPS host. ES modules and Firebase Auth require a web server; opening the HTML as a file may not work.

## Data and limitations

- Reads only `users/{signed-in-uid}/products`, `bills`, `daily_sales`, `expenses`, `branches`, and `returns`.
- The dashboard shows cloud data only. Unsynced phone-local data will not appear.
- This first version is read-only. It does not yet provide editing, branch cash/stock drill-down, restore, or write operations.
- Keep `firebase-config.js` out of version control. Firebase client config is not an authorization boundary; Firestore rules enforce data access.
