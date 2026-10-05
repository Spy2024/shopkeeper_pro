import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';
import '../services/firebase_auth_service.dart';

class AuthProvider extends ChangeNotifier {
  bool isLoggedIn = false;
  String? phoneNumber;
  String? userUid;
  bool isLoading = false;
  String? errorMessage;
  String? demoOtp;

  bool get firebaseAvailable => Firebase.apps.isNotEmpty;

  Future<void> checkExistingSession() async {
    try {
      if (firebaseAvailable) {
        final service = FirebaseAuthService.instance;
        final user = service.currentUser;
        if (user != null) {
          phoneNumber = user.phoneNumber;
          userUid = user.uid;
          isLoggedIn = true;
          notifyListeners();
          return;
        }
      }
    } catch (e) {
      debugPrint('[Auth] Firebase session unavailable: $e');
    }

    final saved = await AuthService.instance.getSession();
    if (saved != null && saved.isNotEmpty) {
      phoneNumber = saved;
      userUid = await AuthService.instance.getUserUid();
      isLoggedIn = userUid != null;
      notifyListeners();
    }
  }

  Future<String> requestOtp(String phone) async {
    isLoading = true;
    errorMessage = null;
    demoOtp = null;
    notifyListeners();
    try {
      if (firebaseAvailable) {
        await FirebaseAuthService.instance.sendOtp(phone);
        return '';
      }
      final otp = await AuthService.instance.sendOtp(phone);
      demoOtp = otp;
      return otp;
    } catch (e) {
      errorMessage = e.toString().replaceFirst('Exception: ', '');
      rethrow;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> confirmOtp(String phone, String otp) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      if (firebaseAvailable) {
        final ok = await FirebaseAuthService.instance.verifyOtp(otp);
        if (ok) {
          final user = FirebaseAuthService.instance.currentUser;
          phoneNumber = user?.phoneNumber ?? phone;
          userUid = user?.uid;
          isLoggedIn = user != null;
        }
        return ok;
      }

      final ok = AuthService.instance.verifyOtp(phone, otp);
      if (ok) {
        await AuthService.instance.persistSession(phone);
        phoneNumber = phone;
        userUid = await AuthService.instance.getUserUid();
        isLoggedIn = true;
        demoOtp = null;
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
    try {
      if (firebaseAvailable) {
        await FirebaseAuthService.instance.clearSession();
      }
    } catch (e) {
      debugPrint('[Auth] Firebase logout unavailable: $e');
    }
    await AuthService.instance.clearSession();
    isLoggedIn = false;
    phoneNumber = null;
    userUid = null;
    demoOtp = null;
    notifyListeners();
  }
}
