import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'db_service.dart';

class AccountDeletionService {
  AccountDeletionService._();
  static final AccountDeletionService instance = AccountDeletionService._();

  Future<void> deleteCurrentAccount(String expectedUserId) async {
    if (expectedUserId.trim().isEmpty ||
        FirebaseAuth.instance.currentUser?.uid != expectedUserId) {
      throw StateError('The signed-in Firebase account does not match this request.');
    }

    final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('deleteMyAccount')
        .call<Map<String, dynamic>>();
    if (result.data['deleted'] != true) {
      throw StateError('The server did not confirm account deletion.');
    }

    await DBService.instance.deleteActiveUserDatabase(expectedUserId);
  }
}
