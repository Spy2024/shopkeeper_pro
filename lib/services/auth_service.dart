import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Phone + OTP authentication.
///
/// IMPORTANT: This class generates and "sends" OTPs locally so the app is
/// fully runnable offline in dev/demo mode. For production you MUST swap
/// `sendOtp()` to call a real SMS provider (Firebase Phone Auth, Twilio
/// Verify, MSG91, etc.) instead of self-generating the code — otherwise
/// anyone can read the code straight out of the app. The rest of the flow
/// (verify, session storage, recovery) stays the same either way.
class AuthService {
  AuthService._internal();
  static final AuthService instance = AuthService._internal();

  final _secureStorage = const FlutterSecureStorage();
  final Map<String, String> _pendingOtps = {}; // phone -> otp (demo only)

  Future<String> sendOtp(String phoneNumber) async {
    // --- DEMO IMPLEMENTATION ---
    // Replace this block with a real SMS API call, e.g.:
    //   await FirebaseAuth.instance.verifyPhoneNumber(...)
    // or
    //   await http.post(Uri.parse('https://your-sms-provider/send'), ...)
    final otp = (100000 + Random().nextInt(899999)).toString();
    _pendingOtps[phoneNumber] = otp;
    return otp; // returned only so the demo UI can show it; a real
    // provider would NOT return the code to the client.
  }

  bool verifyOtp(String phoneNumber, String enteredOtp) {
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
