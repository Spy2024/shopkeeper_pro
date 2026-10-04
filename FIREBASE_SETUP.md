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
