import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';
import '../services/firebase_auth_service.dart';
import '../services/db_service.dart';

class AuthProvider extends ChangeNotifier {
  bool isLoggedIn = false;
  String? phoneNumber;
  String? emailAddress;
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
        if (user != null && user.email != null && !user.emailVerified) {
          await AuthService.instance.clearSession();
          await DBService.instance.clearActiveUser();
          isLoggedIn = false;
          phoneNumber = null;
          emailAddress = null;
          userUid = null;
          notifyListeners();
          return;
        }
        if (user != null) {
          emailAddress = user.email;
          phoneNumber = user.phoneNumber;
          userUid = user.uid;
          await DBService.instance.configureForUser(user.uid);
          isLoggedIn = true;
          notifyListeners();
          return;
        }
        // A configured Firebase app must not silently accept an old local demo
        // session when there is no authenticated Firebase user. Clear any
        // in-memory database connection too, in case this check runs after a
        // session was previously active in the same process.
        await AuthService.instance.clearSession();
        await DBService.instance.clearActiveUser();
        isLoggedIn = false;
        phoneNumber = null;
        emailAddress = null;
        userUid = null;
        notifyListeners();
        return;
      }
    } catch (e) {
      debugPrint('[Auth] Firebase session unavailable: $e');
      // Fail closed when Firebase is configured. Falling back to a cached
      // demo/local session after a Firebase error could expose another local
      // account while the real authenticated identity is unavailable.
      if (firebaseAvailable) {
        try {
          await DBService.instance.clearActiveUser();
        } catch (closeError) {
          debugPrint('[Auth] Could not close the previous local database: $closeError');
        }
        isLoggedIn = false;
        phoneNumber = null;
        emailAddress = null;
        userUid = null;
        notifyListeners();
        return;
      }
    }

    final saved = await AuthService.instance.getSession();
    if (saved != null && saved.isNotEmpty) {
      phoneNumber = saved;
      userUid = await AuthService.instance.getUserUid();
      isLoggedIn = userUid != null;
      if (userUid != null && userUid!.isNotEmpty) {
        try {
          await DBService.instance.configureForUser(userUid!);
        } on LegacyDatabaseMigrationRequired {
          // Keep the user signed out of the data area. They can confirm import
          // through the normal sign-in flow instead of silently assigning data.
          isLoggedIn = false;
          notifyListeners();
          return;
        }
      }
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
        // Android may verify automatically without presenting an SMS code.
        final user = FirebaseAuthService.instance.currentUser;
        if (user != null) {
          // Do not expose the authenticated app state until the account-scoped
          // local database has opened successfully.
          await DBService.instance.configureForUser(user.uid);
          phoneNumber = user.phoneNumber ?? phone;
          userUid = user.uid;
          isLoggedIn = true;
          notifyListeners();
        }
        return '';
      }
      if (!kDebugMode) {
        throw StateError('Firebase is not configured. Demo OTP is disabled in release builds.');
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
        if (!ok) return false;
        final user = FirebaseAuthService.instance.currentUser;
        if (user == null) {
          isLoggedIn = false;
          userUid = null;
          phoneNumber = null;
          errorMessage = 'No authenticated session was created. Please request a new code and try again.';
          return false;
        }
        await DBService.instance.configureForUser(user.uid);
        phoneNumber = user.phoneNumber ?? phone;
        userUid = user.uid;
        isLoggedIn = true;
        return true;
      }

      final ok = AuthService.instance.verifyOtp(phone, otp);
      if (ok) {
        await AuthService.instance.persistSession(phone);
        final verifiedUserId = await AuthService.instance.getUserUid();
        if (verifiedUserId == null || verifiedUserId.trim().isEmpty) {
          throw StateError('Local account identity is unavailable.');
        }
        await DBService.instance.configureForUser(verifiedUserId);
        phoneNumber = phone;
        userUid = verifiedUserId;
        isLoggedIn = true;
        demoOtp = null;
      }
      return ok;
    } on LegacyDatabaseMigrationRequired {
      rethrow;
    } catch (e) {
      errorMessage = e.toString().replaceFirst('Exception: ', '');
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }


  Future<bool> registerWithEmail(String email, String password) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      if (!firebaseAvailable) {
        throw StateError('Configure Firebase before using email accounts.');
      }
      final user = await FirebaseAuthService.instance.createEmailAccount(
        email: email,
        password: password,
      );
      if (user == null) throw StateError('Account creation failed.');
      if (user.emailVerified) {
        await DBService.instance.configureForUser(user.uid);
      }
      emailAddress = user.email;
      userUid = user.uid;
      isLoggedIn = user.emailVerified;
      if (!isLoggedIn) {
        errorMessage = 'Verification email sent. Verify your email, then tap "I have verified".';
      }
      return isLoggedIn;
    } catch (e) {
      errorMessage = e.toString().replaceFirst('Exception: ', '');
      rethrow;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> signInWithEmail(String email, String password) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      if (!firebaseAvailable) {
        throw StateError('Configure Firebase before using email accounts.');
      }
      final user = await FirebaseAuthService.instance.signInWithEmail(
        email: email,
        password: password,
      );
      if (user == null) throw StateError('Sign in failed.');
      if (user.emailVerified) {
        await DBService.instance.configureForUser(user.uid);
      }
      emailAddress = user.email;
      userUid = user.uid;
      isLoggedIn = user.emailVerified;
      if (!isLoggedIn) {
        errorMessage = 'Email is not verified. A verification email has been sent.';
      }
      return isLoggedIn;
    } catch (e) {
      errorMessage = e.toString().replaceFirst('Exception: ', '');
      rethrow;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> refreshEmailVerification() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final verified = await FirebaseAuthService.instance.refreshEmailVerification();
      final user = FirebaseAuthService.instance.currentUser;
      if (verified && user != null) {
        await DBService.instance.configureForUser(user.uid);
        emailAddress = user.email;
        userUid = user.uid;
        isLoggedIn = true;
        return true;
      }
      errorMessage = 'Email is not verified yet. Please check your inbox and spam folder.';
      return false;
    } on LegacyDatabaseMigrationRequired {
      rethrow;
    } catch (e) {
      errorMessage = e.toString().replaceFirst('Exception: ', '');
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Called only after the UI asks the signed-in user to confirm ownership of
  /// an older local database. It imports a copy and leaves the source intact.
  Future<void> migrateLegacyDatabaseForCurrentUser() async {
    String? uid;
    if (firebaseAvailable) {
      uid = FirebaseAuthService.instance.currentUser?.uid;
    } else {
      uid = await AuthService.instance.getUserUid();
    }
    if (uid == null || uid.trim().isEmpty) {
      throw StateError('Sign in again before importing the old local database.');
    }

    await DBService.instance.migrateLegacyDatabaseForUser(
      uid,
      confirmOwnership: true,
    );

    userUid = uid;
    if (firebaseAvailable) {
      final user = FirebaseAuthService.instance.currentUser;
      emailAddress = user?.email;
      phoneNumber = user?.phoneNumber;
    } else {
      phoneNumber = await AuthService.instance.getSession();
    }
    isLoggedIn = true;
    notifyListeners();
  }

  Future<void> sendPasswordReset(String email) async {
    if (!firebaseAvailable) {
      throw StateError('Configure Firebase before resetting an email password.');
    }
    await FirebaseAuthService.instance.sendPasswordReset(email);
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
    await DBService.instance.clearActiveUser();
    isLoggedIn = false;
    phoneNumber = null;
    emailAddress = null;
    userUid = null;
    demoOtp = null;
    notifyListeners();
  }
}
