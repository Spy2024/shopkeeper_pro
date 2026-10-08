# Firebase production setup

This repository intentionally does not invent Firebase project identifiers. The current `lib/firebase_options.dart` still contains placeholder values until the real Firebase project is selected.

## Configure the real project

From the project root:

1. Install Firebase CLI and log in:
   `firebase login`
2. Install FlutterFire CLI:
   `dart pub global activate flutterfire_cli`
3. Configure the existing Firebase project:
   `flutterfire configure`
4. Select the Android app whose package name matches `android/app/build.gradle.kts`.
5. Enable Firebase Authentication > Phone and Cloud Firestore in the Firebase console.
6. Add the Android SHA-1 and SHA-256 fingerprints required by Firebase Phone Authentication.
7. Commit the generated `lib/firebase_options.dart`.

The generated Firebase identifiers are project configuration, not passwords. Never commit service-account private keys or other server credentials.

## Firestore deployment

The repository contains `firestore.rules` and `firebase.json`. After logging in and selecting the correct Firebase project, deploy the rules with:

`firebase deploy --only firestore:rules`

The rules restrict all `users/{userId}/...` data to the authenticated Firebase user whose UID equals `userId`.

## Cloud backup and account deletion

This repository also includes `storage.rules` and a Cloud Function for account deletion.

1. Confirm the selected Firebase project is the intended production project.
2. Enable Firebase Storage and configure Firebase App Check for the Android app.
3. Install Node.js 22 and Firebase CLI.
4. From the repository root, run `cd functions; npm install; npm run lint; cd ..`.
5. Deploy the rules and function with `firebase deploy --only firestore:rules,storage,functions`.
6. Test using a dedicated test account before using real shop data.

The `deleteMyAccount` function requires a recent authentication event (within five minutes) and App Check. It recursively deletes that user's Firestore subtree, removes files under `users/{uid}/` in the configured Storage bucket, then deletes the Firebase Authentication user. Account deletion is irreversible; users should export their records first. The client also deletes the currently active local database after the function confirms success.

Automatic cloud backup is attempted after a successful sync, at most once every 24 hours. If Storage rules or App Check are not configured, the app cannot complete this workflow; inspect the Firebase logs before production release.