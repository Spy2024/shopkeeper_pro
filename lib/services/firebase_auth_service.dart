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
  Future<bool> verifyOtp(String otp) async {
    try {
      if (_verificationId == null) return false;

      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: otp,
      );
      final userCredential = await _firebaseAuth.signInWithCredential(credential);
      final phone = userCredential.user?.phoneNumber;

      if (phone != null) {
        await _secureStorage.write(key: 'session_phone', value: phone);
        await _secureStorage.write(key: 'user_uid', value: userCredential.user!.uid);
        return true;
      }
      return false;
    } catch (e) {
      throw Exception('OTP verification failed: $e');
    }
  }

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
