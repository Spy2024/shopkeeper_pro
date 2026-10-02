import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Demo OTP implementation for local/offline testing.
/// For production, replace with FirebaseAuthService.instance.
class AuthService {
  AuthService._internal();
  static final AuthService instance = AuthService._internal();

  final _secureStorage = const FlutterSecureStorage();
  final Map<String, String> _pendingOtps = {};

  Future<String> sendOtp(String phoneNumber) async {
    final otp = (100000 + Random().nextInt(899999)).toString();
    _pendingOtps[phoneNumber] = otp;
    debugPrint('[AuthService] Demo OTP for $phoneNumber: $otp');
    return otp;
  }

  Future<bool> verifyOtp(String phoneNumber, String enteredOtp) async {
    final expected = _pendingOtps[phoneNumber];
    if (expected != null && expected == enteredOtp) {
      _pendingOtps.remove(phoneNumber);
      return true;
    }
    return false;
  }

  Future<void> persistSession(String phoneNumber) async {
    await _secureStorage.write(key: 'session_phone', value: phoneNumber);
  }

  Future<String?> getSession() async {
    return _secureStorage.read(key: 'session_phone');
  }

  Future<void> clearSession() async {
    await _secureStorage.delete(key: 'session_phone');
  }
}
