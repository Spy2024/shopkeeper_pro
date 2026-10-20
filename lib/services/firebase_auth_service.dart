import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Production-ready Firebase Phone Authentication.
/// Replaces the demo OTP system with real SMS verification.
class FirebaseAuthService {
  FirebaseAuthService._internal();
  static final FirebaseAuthService instance = FirebaseAuthService._internal();

  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final _secureStorage = const FlutterSecureStorage();
  String? _verificationId;
  int? _resendToken;

  /// Send OTP via SMS using Firebase
  Future<void> sendOtp(String phoneNumber) async {
    await _firebaseAuth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) async {
        // Auto-resolve on Android when SIM matches
        await _firebaseAuth.signInWithCredential(credential);
      },
      verificationFailed: (FirebaseAuthException e) {
        throw Exception('Firebase Auth Error: ${e.message}');
      },
      codeSent: (String verificationId, int? resendToken) {
        _verificationId = verificationId;
        _resendToken = resendToken;
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
      },
      timeout: const Duration(minutes: 2),
    );
  }

  /// Verify OTP code
  Future<bool> verifyOtp(String otp, {String? expectedPhone}) async {
    try {
      // Never authenticate without binding the code to the phone requested by the UI.
      if (_verificationId == null || expectedPhone == null || expectedPhone.trim().isEmpty) {
        return false;
      }

      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: otp,
      );
      final userCredential = await _firebaseAuth.signInWithCredential(credential);
      final phone = userCredential.user?.phoneNumber;

      if (phone != null && _normalizePhone(phone) == _normalizePhone(expectedPhone)) {
        await _secureStorage.write(key: 'session_phone', value: phone);
        await _secureStorage.write(key: 'user_uid', value: userCredential.user!.uid);
        _verificationId = null;
        return true;
      }

      // Firebase has already created a credential session at this point. Rejecting
      // the phone match must also revoke that session and remove any stale identity.
      await _firebaseAuth.signOut();
      await _secureStorage.delete(key: 'session_phone');
      await _secureStorage.delete(key: 'user_uid');
      return false;
    } catch (e) {
      throw Exception('OTP verification failed: $e');
    }
  }

  String _normalizePhone(String value) => value.replaceAll(RegExp(r'[^0-9+]'), '');

  /// Get current user UID for Firestore sync
  Future<String?> getUserUid() async {
    return _firebaseAuth.currentUser?.uid ?? await _secureStorage.read(key: 'user_uid');
  }

  /// Check if user is already logged in
  Future<String?> getSession() async {
    return _secureStorage.read(key: 'session_phone');
  }

  /// Logout and clear session
  Future<void> clearSession() async {
    await _firebaseAuth.signOut();
    await _secureStorage.delete(key: 'session_phone');
    await _secureStorage.delete(key: 'user_uid');
  }
}
