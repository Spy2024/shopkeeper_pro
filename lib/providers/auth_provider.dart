import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  bool isLoggedIn = false;
  String? phoneNumber;
  bool isLoading = false;

  Future<void> checkExistingSession() async {
    try {
      final saved = await AuthService.instance.getSession();
      if (saved != null) {
        phoneNumber = saved;
        isLoggedIn = true;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[AuthProvider] Error checking session: $e');
    }
  }

  Future<String> requestOtp(String phone) async {
    isLoading = true;
    notifyListeners();
    try {
      final otp = await AuthService.instance.sendOtp(phone);
      return otp;
    } catch (e) {
      debugPrint('[AuthProvider] Error requesting OTP: $e');
      rethrow;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> confirmOtp(String phone, String otp) async {
    try {
      final ok = await AuthService.instance.verifyOtp(phone, otp);
      if (ok) {
        phoneNumber = phone;
        isLoggedIn = true;
        await AuthService.instance.persistSession(phone);
        notifyListeners();
      }
      return ok;
    } catch (e) {
      debugPrint('[AuthProvider] Error confirming OTP: $e');
      return false;
    }
  }

  Future<void> logout() async {
    try {
      await AuthService.instance.clearSession();
      isLoggedIn = false;
      phoneNumber = null;
      notifyListeners();
    } catch (e) {
      debugPrint('[AuthProvider] Error during logout: $e');
    }
  }
}
