import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shopkeeper_pro/services/db_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String userA;
  late String userB;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    final suffix = DateTime.now().microsecondsSinceEpoch;
    userA = 'isolation-a-$suffix';
    userB = 'isolation-b-$suffix';
    await DBService.instance.clearActiveUser();
  });

  tearDown(() async {
    await DBService.instance.clearActiveUser();
    await DBService.instance.configureForUser(userA);
    await DBService.instance.deleteActiveUserDatabase(userA);
    await DBService.instance.configureForUser(userB);
    await DBService.instance.deleteActiveUserDatabase(userB);
  });

  test('switching accounts opens isolated SQLite databases', () async {
    await DBService.instance.configureForUser(userA);
    var db = await DBService.instance.database;
    await db.insert('shop', {'id': 'shop-a', 'name': 'Account A'});

    await DBService.instance.configureForUser(userB);
    db = await DBService.instance.database;
    expect(await db.query('shop'), isEmpty);
    await db.insert('shop', {'id': 'shop-b', 'name': 'Account B'});

    await DBService.instance.configureForUser(userA);
    db = await DBService.instance.database;
    expect((await db.query('shop')).single['name'], 'Account A');

    await DBService.instance.configureForUser(userB);
    db = await DBService.instance.database;
    expect((await db.query('shop')).single['name'], 'Account B');
  });
}
