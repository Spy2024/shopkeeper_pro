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
}
