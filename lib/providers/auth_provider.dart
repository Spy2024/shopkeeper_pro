import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  bool isLoggedIn = false;
  String? phoneNumber;
  String? userUid;
  bool isLoading = false;

  Future<void> checkExistingSession() async {
    final saved = await AuthService.instance.getSession();
    if (saved != null && saved.isNotEmpty) {
      phoneNumber = saved;
      userUid = await AuthService.instance.getUserUid();
      isLoggedIn = true;
      notifyListeners();
    }
  }

  Future<String> requestOtp(String phone) async {
    isLoading = true;
    notifyListeners();
    try {
      return await AuthService.instance.sendOtp(phone);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> confirmOtp(String phone, String otp) async {
    final ok = AuthService.instance.verifyOtp(phone, otp);
    if (!ok) return false;

    await AuthService.instance.persistSession(phone);
    phoneNumber = phone;
    userUid = await AuthService.instance.getUserUid();
    isLoggedIn = true;
    notifyListeners();
    return true;
  }

  Future<void> logout() async {
    await AuthService.instance.clearSession();
    isLoggedIn = false;
    phoneNumber = null;
    userUid = null;
    notifyListeners();
  }
}
