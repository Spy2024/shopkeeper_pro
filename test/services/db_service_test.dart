import 'package:flutter_test/flutter_test.dart';
import 'package:shopkeeper_pro/services/db_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('database access fails closed when no account is active', () async {
    await DBService.instance.clearActiveUser();

    await expectLater(
      DBService.instance.database,
      throwsA(isA<StateError>()),
    );
  });

  group('Account database filename isolation', () {
    test('uses distinct filename tokens for distinct account IDs', () {
      expect(
        databaseFileTokenForUser('tenant/a'),
        isNot(databaseFileTokenForUser('tenant_a')),
      );
    });

    test('preserves legacy filenames for ordinary Firebase UIDs', () {
      expect(databaseFileTokenForUser('firebase-user-123'), 'firebase-user-123');
    });

    test('generates a stable token for the same account ID', () {
      expect(
        databaseFileTokenForUser('firebase-user-123'),
        databaseFileTokenForUser('firebase-user-123'),
      );
    });

    test('rejects empty account IDs', () {
      expect(() => databaseFileTokenForUser('  '), throwsArgumentError);
    });
  });
}
