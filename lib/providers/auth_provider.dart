import 'package:flutter/foundation.dart';
import '../services/firebase_auth_service.dart';

class AuthProvider extends ChangeNotifier {
  bool isLoggedIn = false;
  String? phoneNumber;
  String? userUid;
  bool isLoading = false;
  String? errorMessage;

  Future<void> checkExistingSession() async {
    final service = FirebaseAuthService.instance;
    final user = service.currentUser;
    if (user != null) {
      phoneNumber = user.phoneNumber;
      userUid = user.uid;
      isLoggedIn = true;
      notifyListeners();
    }
  }

  Future<String> requestOtp(String phone) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await FirebaseAuthService.instance.sendOtp(phone);
      return '';
    } catch (e) {
      errorMessage = e.toString().replaceFirst('Exception: ', '');
      rethrow;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> confirmOtp(String otp) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final ok = await FirebaseAuthService.instance.verifyOtp(otp);
      if (ok) {
        final user = FirebaseAuthService.instance.currentUser;
        phoneNumber = user?.phoneNumber;
        userUid = user?.uid;
        isLoggedIn = user != null;
      }
      return ok;
    } catch (e) {
      errorMessage = e.toString().replaceFirst('Exception: ', '');
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await FirebaseAuthService.instance.clearSession();
    isLoggedIn = false;
    phoneNumber = null;
    userUid = null;
    notifyListeners();
  }
}
