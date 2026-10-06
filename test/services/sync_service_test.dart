import 'package:flutter_test/flutter_test.dart';

import 'package:shopkeeper_pro/services/sync_service.dart';

void main() {
  group('SyncService concurrency', () {
    test('coalesced sync calls never leave the service locked', () async {
      final service = SyncService.instance;

      await Future.wait([
        service.syncNow('test-user'),
        service.syncNow('test-user'),
        service.syncFromCloud('test-user'),
      ]);

      expect(service.isSyncing, isFalse);
    });
  });
}
