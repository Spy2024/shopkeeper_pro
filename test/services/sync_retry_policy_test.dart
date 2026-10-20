import 'package:flutter_test/flutter_test.dart';
import 'package:shopkeeper_pro/services/sync_queue_service.dart';

void main() {
  group('sync queue retry policy', () {
    test('uses increasing delays for repeated failures', () {
      expect(syncRetryDelayForAttempt(1), const Duration(seconds: 1));
      expect(syncRetryDelayForAttempt(2), const Duration(seconds: 2));
      expect(syncRetryDelayForAttempt(3), const Duration(seconds: 4));
      expect(syncRetryDelayForAttempt(4), const Duration(seconds: 8));
    });

    test('caps retry delay for long outages', () {
      expect(syncRetryDelayForAttempt(9), const Duration(seconds: 256));
      expect(syncRetryDelayForAttempt(100), const Duration(seconds: 256));
    });

    test('rejects invalid retry attempt number', () {
      expect(() => syncRetryDelayForAttempt(0), throwsArgumentError);
      expect(() => syncRetryDelayForAttempt(-2), throwsArgumentError);
    });
  });
}
