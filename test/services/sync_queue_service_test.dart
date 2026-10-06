import 'package:flutter_test/flutter_test.dart';
import 'package:shopkeeper_pro/services/sync_queue_service.dart';

void main() {
  group('SyncOperation', () {
    test('round trips nested JSON payload without losing data', () {
      const operation = SyncOperation(
        id: 'products-p1-1',
        operation: 'update',
        tableName: 'products',
        documentId: 'p1',
        data: {
          'id': 'p1',
          'name': 'Tea',
          'stockQuantity': 7,
          'nested': {'source': 'offline'},
        },
        timestamp: 123,
      );

      final restored = SyncOperation.fromMap({
        'id': operation.id,
        'operation': operation.operation,
        'tableName': operation.tableName,
        'documentId': operation.documentId,
        'data': operation.dataAsJson,
        'timestamp': operation.timestamp,
        'attempts': 2,
        'nextRetryAt': 456,
        'lastError': 'network',
      });

      expect(restored.data['name'], 'Tea');
      expect(restored.data['stockQuantity'], 7);
      expect(restored.data['nested'], {'source': 'offline'});
      expect(restored.attempts, 2);
      expect(restored.nextRetryAt, 456);
      expect(restored.lastError, 'network');
    });
  });
}
