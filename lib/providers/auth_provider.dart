import 'package:flutter/foundation.dart';
import '../services/firebase_auth_service.dart';
import '../services/db_service.dart';

class AuthProvider extends ChangeNotifier {
  bool isLoggedIn = false;
  String? phoneNumber;
  String? userUid;
  bool isLoading = false;

  Future<void> checkExistingSession() async {
    final saved = await FirebaseAuthService.instance.getSession();
    if (saved != null && saved.isNotEmpty) {
      final uid = await FirebaseAuthService.instance.getUserUid();
      if (uid == null || uid.isEmpty) return;
      await DBService.instance.configureForUser(uid);
      phoneNumber = saved;
      userUid = uid;
      isLoggedIn = true;
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

  Future<bool> confirmOtp(String phone, String otp) async {
    final ok = await FirebaseAuthService.instance.verifyOtp(otp, expectedPhone: phone);
    if (!ok) return false;

    final uid = await FirebaseAuthService.instance.getUserUid();
    if (uid == null || uid.isEmpty) return false;
    await DBService.instance.configureForUser(uid);
    phoneNumber = phone;
    userUid = uid;
    isLoggedIn = true;
    notifyListeners();
    return true;
  }

  Future<void> logout() async {
    await FirebaseAuthService.instance.clearSession();
    await DBService.instance.clearActiveUser();
    isLoggedIn = false;
    phoneNumber = null;
    userUid = null;
    notifyListeners();
  }
}
