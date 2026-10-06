import 'package:flutter/foundation.dart';
import '../services/firebase_auth_service.dart';

class AuthProvider extends ChangeNotifier {
  bool isLoggedIn = false;
  String? phoneNumber;
  String? userUid;
  bool isLoading = false;

  Future<void> checkExistingSession() async {
    final saved = await FirebaseAuthService.instance.getSession();
    if (saved != null && saved.isNotEmpty) {
      phoneNumber = saved;
      userUid = await FirebaseAuthService.instance.getUserUid();
      isLoggedIn = userUid != null;
      notifyListeners();
    }
  }

  Future<void> requestOtp(String phone) async {
    isLoading = true;
    notifyListeners();
    try {
      await FirebaseAuthService.instance.sendOtp(phone);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> confirmOtp(String otp) async {
    final ok = await FirebaseAuthService.instance.verifyOtp(otp);
    if (!ok) return false;

    userUid = await FirebaseAuthService.instance.getUserUid();
    phoneNumber = await FirebaseAuthService.instance.getSession();
    isLoggedIn = userUid != null;
    notifyListeners();
    return isLoggedIn;
  }

  Future<void> logout() async {
    await FirebaseAuthService.instance.clearSession();
    isLoggedIn = false;
    phoneNumber = null;
    userUid = null;
    notifyListeners();
  }
}
