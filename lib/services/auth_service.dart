import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final Map<String, String> _pendingOtps = {};
  String? lastDemoOtp;

  Future<String> sendOtp(String phone) async {
    final otp = (100000 + Random().nextInt(900000)).toString();
    _pendingOtps[phone] = otp;
    lastDemoOtp = otp;
    return otp;
  }

  bool verifyOtp(String phone, String otp) {
    final expected = _pendingOtps[phone];
    if (expected == null || expected != otp) return false;
    _pendingOtps.remove(phone);
    return true;
  }

  Future<void> persistSession(String phone) async {
    final normalized = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    await _storage.write(key: 'session_phone', value: phone);
    await _storage.write(
      key: 'user_uid',
      value: 'local_${normalized.replaceAll('+', '')}',
    );
  }

  Future<String?> getSession() => _storage.read(key: 'session_phone');
  Future<String?> getUserUid() => _storage.read(key: 'user_uid');

  Future<void> clearSession() async {
    await _storage.delete(key: 'session_phone');
    await _storage.delete(key: 'user_uid');
  }
}
