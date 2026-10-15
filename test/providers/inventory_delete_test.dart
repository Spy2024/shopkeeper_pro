import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shopkeeper_pro/providers/inventory_provider.dart';
import 'package:shopkeeper_pro/services/db_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String userId;
  late InventoryProvider inventory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    userId = 'inventory-delete-${DateTime.now().microsecondsSinceEpoch}';
    await DBService.instance.clearActiveUser();
    await DBService.instance.configureForUser(userId);
    final db = await DBService.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.insert('branches', {
      'id': 'branch-1',
      'name': 'Main',
      'code': 'MAIN',
      'isMain': 1,
      'isActive': 1,
      'createdAt': now,
    });
    await db.insert('products', {
      'id': 'product-1',
      'name': 'Tea',
      'category': 'Grocery',
      'stockQuantity': 5,
      'costPrice': 40.0,
      'sellingPrice': 100.0,
      'lowStockThreshold': 1,
    });
    await db.insert('branch_stock', {
      'branchId': 'branch-1',
      'productId': 'product-1',
      'quantity': 5,
      'updatedAt': now,
    });
    inventory = InventoryProvider();
    await inventory.load();
  });

  tearDown(() async {
    if (DBService.instance.activeUserId == userId) {
      await DBService.instance.deleteActiveUserDatabase(userId);
    }
  });

  test('refuses product deletion while inventory remains and queues no tombstone', () async {
    await expectLater(inventory.deleteProduct('product-1'), throwsA(isA<StateError>()));
    final db = await DBService.instance.database;
    expect(await db.query('products', where: 'id = ?', whereArgs: ['product-1']), hasLength(1));
    expect(await db.query('sync_queue', where: 'operation = ?', whereArgs: ['delete']), isEmpty);
  });

  test('deletes zero-stock product and tombstone atomically', () async {
    final db = await DBService.instance.database;
    await db.update('products', {'stockQuantity': 0}, where: 'id = ?', whereArgs: ['product-1']);
    await db.update('branch_stock', {'quantity': 0}, where: 'productId = ?', whereArgs: ['product-1']);

    await inventory.deleteProduct('product-1');

    expect(await db.query('products', where: 'id = ?', whereArgs: ['product-1']), isEmpty);
    expect(await db.query('branch_stock', where: 'productId = ?', whereArgs: ['product-1']), isEmpty);
    final tombstones = await db.query(
      'sync_queue',
      where: 'operation = ? AND tableName = ? AND documentId = ?',
      whereArgs: ['delete', 'products', 'product-1'],
    );
    expect(tombstones, hasLength(1));
  });
}
