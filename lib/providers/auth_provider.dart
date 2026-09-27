import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  bool isLoggedIn = false;
  String? phoneNumber;
  bool isLoading = false;

  Future<void> checkExistingSession() async {
    final saved = await AuthService.instance.getSession();
    if (saved != null) {
      phoneNumber = saved;
      isLoggedIn = true;
      notifyListeners();
    }
  }

  Future<String> requestOtp(String phone) async {
    isLoading = true;
    notifyListeners();
    final otp = await AuthService.instance.sendOtp(phone);
    isLoading = false;
    notifyListeners();
    return otp;
  }

  Future<bool> confirmOtp(String phone, String otp) async {
    final ok = AuthService.instance.verifyOtp(phone, otp);
    if (ok) {
      phoneNumber = phone;
      isLoggedIn = true;
      await AuthService.instance.persistSession(phone);
      notifyListeners();
    }
    return ok;
  }

  Future<void> logout() async {
    await AuthService.instance.clearSession();
    isLoggedIn = false;
    phoneNumber = null;
    notifyListeners();
  }
}
