import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shopkeeper_pro/services/db_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String userId;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    userId = 'migration-${DateTime.now().microsecondsSinceEpoch}';
    await DBService.instance.clearActiveUser();
  });

  tearDown(() async {
    if (DBService.instance.activeUserId == userId) {
      await DBService.instance.deleteActiveUserDatabase(userId);
    }
  });

  test('schema v16 upgrades billing fields and creates mobile shop tables', () async {
    final path = p.join(await getDatabasesPath(), 'shopkeeper_pro_$userId.db');
    final oldDb = await openDatabase(
      path,
      version: 16,
      onCreate: (db, _) async {
        await db.execute(
          'CREATE TABLE bills (id TEXT PRIMARY KEY, date TEXT NOT NULL, customerName TEXT, '
          'customerAddress TEXT, customerPhone TEXT, customerEmail TEXT, discount REAL NOT NULL DEFAULT 0, '
          'taxPercent REAL NOT NULL DEFAULT 0, branchId TEXT)',
        );
        await db.execute(
          'CREATE TABLE bill_returns (id TEXT PRIMARY KEY, billId TEXT NOT NULL, productId TEXT NOT NULL, '
          'productName TEXT NOT NULL, unitPrice REAL NOT NULL DEFAULT 0, quantity INTEGER NOT NULL CHECK(quantity > 0), '
          'refundAmount REAL NOT NULL, date TEXT NOT NULL, reason TEXT NOT NULL, branchId TEXT)',
        );
        await db.execute(
          'CREATE TABLE bill_items (id INTEGER PRIMARY KEY AUTOINCREMENT, billId TEXT NOT NULL, '
          'productId TEXT, productName TEXT NOT NULL, quantity INTEGER NOT NULL, '
          'unitPrice REAL NOT NULL, cloudId TEXT)',
        );
      },
    );
    await oldDb.close();

    await DBService.instance.configureForUser(userId);
    final db = await DBService.instance.database;
    final billColumns = await db.rawQuery('PRAGMA table_info(bills)');
    final returnColumns = await db.rawQuery('PRAGMA table_info(bill_returns)');

    expect(billColumns.map((column) => column['name']), contains('customerId'));
    expect(returnColumns.map((column) => column['name']), containsAll(['refundMethod', 'mobileDeviceId']));
    final billItemColumns = await db.rawQuery('PRAGMA table_info(bill_items)');
    expect(billItemColumns.map((column) => column['name']), containsAll(['mobileDeviceId', 'mobileImei']));
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final tableNames = tables.map((row) => row['name']).toSet();
    expect(tableNames, containsAll([
      'mobile_devices',
      'mobile_repair_jobs',
      'mobile_repair_job_parts',
    ]));
    final deviceColumns = await db.rawQuery('PRAGMA table_info(mobile_devices)');
    expect(deviceColumns.map((column) => column['name']), containsAll([
      'imei1', 'imei2', 'conditionGrade', 'purchasePrice', 'repairCost',
      'sellingPrice', 'inspectionJson', 'status', 'soldBillId',
    ]));
  });
}
