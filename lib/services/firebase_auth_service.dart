import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class FirebaseAuthService {
  FirebaseAuthService._internal();
  static final FirebaseAuthService instance = FirebaseAuthService._internal();

  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final _secureStorage = const FlutterSecureStorage();
  String? _verificationId;

  Future<void> sendOtp(String phoneNumber) async {
    final completer = Completer<void>();

    void complete() {
      if (!completer.isCompleted) completer.complete();
    }

    void fail(Object error, [StackTrace? stackTrace]) {
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
    }

    await _firebaseAuth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) async {
        try {
          await _firebaseAuth.signInWithCredential(credential);
          complete();
        } catch (e, st) {
          fail(e, st);
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        fail(Exception('Firebase Auth Error: ${e.message ?? e.code}'));
      },
      codeSent: (String verificationId, int? _) {
        _verificationId = verificationId;
        complete();
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
      },
      timeout: const Duration(minutes: 2),
    );

    await completer.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () => throw TimeoutException('Firebase OTP request timed out'),
    );
  }

  Future<bool> verifyOtp(String otp) async {
    try {
      final verificationId = _verificationId;
      if (verificationId == null || otp.length != 6) return false;

      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: otp,
      );
      final userCredential = await _firebaseAuth.signInWithCredential(credential);
      final user = userCredential.user;
      final phone = user?.phoneNumber;
      if (user == null || phone == null) return false;

      await _secureStorage.write(key: 'session_phone', value: phone);
      await _secureStorage.write(key: 'user_uid', value: user.uid);
      _verificationId = null;
      return true;
    } catch (e) {
      throw Exception('OTP verification failed: ${e}');
    }
  }

  Future<String?> getUserUid() async {
    return _firebaseAuth.currentUser?.uid ?? await _secureStorage.read(key: 'user_uid');
  }

  Future<String?> getSession() async {
    return _secureStorage.read(key: 'session_phone');
  }

  Future<void> clearSession() async {
    await _firebaseAuth.signOut();
    _verificationId = null;
    await _secureStorage.delete(key: 'session_phone');
    await _secureStorage.delete(key: 'user_uid');
  }
}
