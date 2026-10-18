import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Firebase Phone Authentication with a persisted session only after a
/// Firebase credential has actually been accepted.
class FirebaseAuthService {
  FirebaseAuthService._internal();
  static final FirebaseAuthService instance = FirebaseAuthService._internal();

  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final _secureStorage = const FlutterSecureStorage();
  String? _verificationId;
  int? _resendToken;

  Future<void> sendOtp(String phoneNumber) async {
    final completer = Completer<void>();
    await _firebaseAuth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) async {
        try {
          final result = await _firebaseAuth.signInWithCredential(credential);
          final user = result.user;
          if (user == null) throw StateError('Firebase returned no authenticated user.');
          await _persistUser(user);
          if (!completer.isCompleted) completer.complete();
        } catch (error, stackTrace) {
          if (!completer.isCompleted) completer.completeError(error, stackTrace);
        }
      },
      verificationFailed: (FirebaseAuthException error) {
        if (!completer.isCompleted) {
          completer.completeError(Exception('Firebase Auth Error: ${error.message}'));
        }
      },
      codeSent: (String verificationId, int? resendToken) {
        _verificationId = verificationId;
        _resendToken = resendToken;
        if (!completer.isCompleted) completer.complete();
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
        if (!completer.isCompleted) completer.complete();
      },
      timeout: const Duration(minutes: 2),
    );
    await completer.future;
  }

  Future<bool> verifyOtp(String otp, {String? expectedPhone}) async {
    try {
      final verificationId = _verificationId;
      if (verificationId == null || otp.trim().length != 6) return false;
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: otp.trim(),
      );
      final result = await _firebaseAuth.signInWithCredential(credential);
      final user = result.user;
      final phone = user?.phoneNumber;
      if (user == null || phone == null ||
          (expectedPhone != null && _normalizePhone(phone) != _normalizePhone(expectedPhone))) {
        await _firebaseAuth.signOut();
        return false;
      }
      await _persistUser(user);
      return true;
    } on FirebaseAuthException catch (error) {
      debugPrint('[FirebaseAuth] OTP verification failed: ${error.code}');
      throw Exception('OTP verification failed: ${error.message}');
    }
  }

  Future<void> _persistUser(User user) async {
    final phone = user.phoneNumber;
    if (phone != null) {
      await _secureStorage.write(key: 'session_phone', value: phone);
    }
    await _secureStorage.write(key: 'user_uid', value: user.uid);
  }

  String _normalizePhone(String value) => value.replaceAll(RegExp(r'[^0-9+]'), '');

  /// A cached UID alone is not proof of an active Firebase session.
  Future<String?> getUserUid() async => _firebaseAuth.currentUser?.uid;

  Future<String?> getSession() async => _secureStorage.read(key: 'session_phone');

  Future<void> clearSession() async {
    await _firebaseAuth.signOut();
    await _secureStorage.delete(key: 'session_phone');
    await _secureStorage.delete(key: 'user_uid');
    _verificationId = null;
    _resendToken = null;
  }
}
