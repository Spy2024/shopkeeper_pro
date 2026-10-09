import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Firebase Phone Authentication service.
class FirebaseAuthService {
  FirebaseAuthService._internal();
  static final FirebaseAuthService instance = FirebaseAuthService._internal();

  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final _secureStorage = const FlutterSecureStorage();
  String? _verificationId;
  int? _resendToken;

  User? get currentUser => _firebaseAuth.currentUser;
  int? get resendToken => _resendToken;

  Future<void> sendOtp(String phoneNumber) async {
    final completer = Completer<void>();
    await _firebaseAuth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) async {
        try {
          await _firebaseAuth.signInWithCredential(credential);
          await _persistCurrentUser();
          if (!completer.isCompleted) completer.complete();
        } catch (e) {
          if (!completer.isCompleted) completer.completeError(e);
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        if (!completer.isCompleted) {
          completer.completeError(
            Exception(e.message ?? 'Firebase phone authentication failed.'),
          );
        }
      },
      codeSent: (String verificationId, int? resendToken) {
        _verificationId = verificationId;
        _resendToken = resendToken;
        if (!completer.isCompleted) completer.complete();
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
      },
      timeout: const Duration(minutes: 2),
    );
    await completer.future;
  }

  Future<bool> verifyOtp(String otp) async {
    try {
      final verificationId = _verificationId;
      if (verificationId == null) return false;

      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: otp,
      );
      await _firebaseAuth.signInWithCredential(credential);
      await _persistCurrentUser();
      _verificationId = null;
      return _firebaseAuth.currentUser != null;
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message ?? 'OTP verification failed.');
    }
  }


  Future<User?> createEmailAccount({
    required String email,
    required String password,
  }) async {
    final credential = await _firebaseAuth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user;
    if (user == null) throw StateError('Firebase did not return the new account.');
    await user.sendEmailVerification();
    await _secureStorage.write(key: 'session_email', value: user.email);
    await _secureStorage.write(key: 'user_uid', value: user.uid);
    return user;
  }

  Future<User?> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final credential = await _firebaseAuth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user;
    if (user != null) {
      await _secureStorage.write(key: 'session_email', value: user.email);
      await _secureStorage.write(key: 'user_uid', value: user.uid);
      if (!user.emailVerified) await user.sendEmailVerification();
    }
    return user;
  }

  Future<bool> refreshEmailVerification() async {
    await _firebaseAuth.currentUser?.reload();
    final user = _firebaseAuth.currentUser;
    if (user == null) return false;
    if (user.emailVerified) {
      await _secureStorage.write(key: 'session_email', value: user.email);
      await _secureStorage.write(key: 'user_uid', value: user.uid);
      return true;
    }
    return false;
  }

  Future<void> sendPasswordReset(String email) =>
      _firebaseAuth.sendPasswordResetEmail(email: email.trim());

  Future<void> _persistCurrentUser() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return;
    final phone = user.phoneNumber;
    if (phone != null) {
      await _secureStorage.write(key: 'session_phone', value: phone);
    }
    await _secureStorage.write(key: 'user_uid', value: user.uid);
  }

  Future<String?> getUserUid() async => _firebaseAuth.currentUser?.uid;

  Future<String?> getSession() async =>
      _firebaseAuth.currentUser?.phoneNumber ??
      await _secureStorage.read(key: 'session_phone');

  Future<void> clearSession() async {
    await _firebaseAuth.signOut();
    await _secureStorage.delete(key: 'session_phone');
    await _secureStorage.delete(key: 'session_email');
    await _secureStorage.delete(key: 'user_uid');
    _verificationId = null;
    _resendToken = null;
  }
}
