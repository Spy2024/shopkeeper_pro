# Production Setup Guide

## 1. Multi-Device Sync (Firebase Firestore)

### What's Fixed:
- **Before**: App only had local SQLite, no cloud sync
- **After**: `SyncService` syncs all data to Firebase Firestore
  - Automatic sync when device comes online
  - Supports multiple devices for same user
  - All tables (products, bills, suppliers, sales, expenses) synced

### Setup Steps:
1. Create Firebase project: https://console.firebase.google.com
2. Enable Cloud Firestore for your project
3. Update `lib/firebase_options.dart` with your credentials
4. Run: `flutter pub get`
5. Initialize sync in `AuthProvider` after login (see code below)

### Usage:
```dart
// After user logs in, call this:
await SyncService.instance.init(userId);
await SyncService.instance.syncFromCloud(userId);
```

---

## 2. Production Authentication (Firebase Phone Auth)

### What's Fixed:
- **Before**: OTP generated locally (security risk)
- **After**: Uses Firebase Phone Authentication (production-ready)
  - Real SMS sent to user's phone
  - No OTP visible in app code
  - Server-side verification
  - Works offline too (caches verification)

### Setup Steps:
1. Enable "Phone" sign-in in Firebase Console → Authentication → Sign-in method
2. Update `AuthProvider` to use `FirebaseAuthService` instead of `AuthService`

### Code Change:
```dart
// OLD (in lib/screens/auth/phone_entry_screen.dart)
final otp = await auth.requestOtp(phone);

// NEW (switch to Firebase)
final otp = await FirebaseAuthService.instance.sendOtp(phone);
// Don't display OTP to user - Firebase handles it
```

---

## 3. PDF Invoice with Logo

### What's Fixed:
- **Before**: Shop logo stored in database but not used in PDF
- **After**: Logo embedded in invoice PDF if available
  - Loads image from file system
  - Gracefully skips if logo missing
  - Supports customization (size, position)

### How it Works:
```dart
// In PdfService.generateInvoice():
if (shop?.logoPath != null) {
  logoImage = pw.MemoryImage(await logoFile.readAsBytes());
  // Logo appears in PDF header
}
```

---

## Firebase Security Rules (Copy to Firestore)

```firestore
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read, write: if request.auth.uid == userId;
      
      match /{document=**} {
        allow read, write: if request.auth.uid == userId;
      }
    }
  }
}
```

---

## Testing

### Test Multi-Device Sync:
1. Create account on Device A
2. Add products/bills on Device A
3. Open app on Device B with same phone number
4. Products/bills should sync automatically

### Test Firebase Auth:
1. Enter phone number
2. Receive SMS with OTP (not shown in app)
3. Enter code and verify
4. Should see Firestore user document created

### Test Invoice Logo:
1. Go to Shop Profile
2. Upload shop logo
3. Create bill and checkout
4. Generated PDF should include logo in header

---

## Deployment Checklist

- [ ] Firebase project created and configured
- [ ] Firestore Security Rules updated
- [ ] Firebase credentials added to `firebase_options.dart`
- [ ] AuthProvider updated to use FirebaseAuthService
- [ ] SyncService initialized after login
- [ ] Test sync on 2+ devices
- [ ] Test invoice generation with logo
- [ ] Remove debug comments and demo OTP code
- [ ] Update app version in pubspec.yaml
- [ ] Build release APK/IPA

---

## Troubleshooting

### Sync not working?
- Check internet connectivity
- Verify Firebase credentials in firebase_options.dart
- Check Firestore Security Rules
- Look at device logs: `flutter logs`

### OTP not received?
- Verify phone number format (include country code, e.g., +92XXXXXXXXXX)
- Check Firebase Phone Auth is enabled
- Wait 2 minutes for SMS to arrive
- Check app has SMS permission on Android

### Logo not appearing in PDF?
- Verify logo file exists at `shop.logoPath`
- Check file permissions
- Try with a different image format
- Check PDF viewer supports images
