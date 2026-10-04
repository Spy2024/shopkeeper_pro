# Android release signing

The app no longer uses the Android debug keystore for release builds.

For a real production/Play Store build, add these GitHub Actions secrets:

- `ANDROID_KEYSTORE_BASE64`: base64-encoded production `.jks`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

The workflow will use that keystore when the secrets exist. If they are not configured, CI generates a temporary CI-only signing key so the release APK is signed without exposing or reusing the debug key. That temporary key must not be used for a production release.

Local release builds can provide the same four environment variables before running `flutter build apk --release`.
