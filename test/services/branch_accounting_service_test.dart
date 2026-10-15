import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shopkeeper_pro/services/branch_accounting_service.dart';
import 'package:shopkeeper_pro/services/db_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var userId = '';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    userId = 'branch-accounting-${DateTime.now().microsecondsSinceEpoch}';
    await DBService.instance.clearActiveUser();
    await DBService.instance.configureForUser(userId);
    final db = await DBService.instance.database;
    final now = DateTime.now().toIso8601String();
    for (final branch in [
      {'id': 'b1', 'name': 'Main', 'code': 'MAIN'},
      {'id': 'b2', 'name': 'Second', 'code': 'SEC'},
    ]) {
      await db.insert('branches', {
        ...branch,
        'createdAt': now,
        'isMain': branch['id'] == 'b1' ? 1 : 0,
        'isActive': 1,
      });
    }
    await db.insert('products', {
      'id': 'p1',
      'name': 'Tea',
      'category': 'Grocery',
      'stockQuantity': 20,
      'costPrice': 100.0,
      'sellingPrice': 150.0,
      'lowStockThreshold': 5,
    });
    await db.insert('bills', {
      'id': 'bill-1',
      'date': now,
      'discount': 0.0,
      'taxPercent': 0.0,
      'branchId': 'b1',
    });
  });

  tearDown(() async {
    if (DBService.instance.activeUserId == userId) {
      await DBService.instance.deleteActiveUserDatabase(userId);
    }
  });

  test('stock transfer is atomic and conserves branch quantity', () async {
    final service = BranchAccountingService.instance;
    await service.setBranchStock(branchId: 'b1', productId: 'p1', quantity: 5);

    await service.transferStock(
      fromBranchId: 'b1',
      toBranchId: 'b2',
      productId: 'p1',
      quantity: 3,
    );

    expect(await service.branchStock('b1', 'p1'), 2);
    expect(await service.branchStock('b2', 'p1'), 3);
    final db = await DBService.instance.database;
    expect(await db.query('stock_transfers'), hasLength(1));

    await expectLater(
      service.transferStock(
        fromBranchId: 'b1',
        toBranchId: 'b2',
        productId: 'p1',
        quantity: 3,
      ),
      throwsA(isA<StateError>()),
    );
    expect(await service.branchStock('b1', 'p1'), 2);
    expect(await service.branchStock('b2', 'p1'), 3);
    expect(await db.query('stock_transfers'), hasLength(1));
  });

  test('branch allocation cannot exceed stock left after other branches', () async {
    final service = BranchAccountingService.instance;
    await service.setBranchStock(branchId: 'b1', productId: 'p1', quantity: 15);

    await expectLater(
      service.setBranchStock(branchId: 'b2', productId: 'p1', quantity: 6),
      throwsA(isA<StateError>()),
    );
    expect(await service.branchStock('b1', 'p1'), 15);
    expect(await service.branchStock('b2', 'p1'), 0);
  });

  test('split tender rejects allocations below the bill total', () async {
    await expectLater(
      BranchAccountingService.instance.recordPaymentAllocations(
        billId: 'bill-1',
        billTotal: 100,
        allocations: const [
          PaymentAllocationInput(method: 'cash', amount: 40),
          PaymentAllocationInput(method: 'credit', amount: 50),
        ],
      ),
      throwsA(isA<ArgumentError>()),
    );
    final db = await DBService.instance.database;
    expect(await db.query('payment_allocations'), isEmpty);
  });

  test('split tender saves allocations that exactly equal the bill total', () async {
    await BranchAccountingService.instance.recordPaymentAllocations(
      billId: 'bill-1',
      billTotal: 100,
      allocations: const [
        PaymentAllocationInput(method: 'cash', amount: 60),
        PaymentAllocationInput(method: 'credit', amount: 40),
      ],
    );
    final db = await DBService.instance.database;
    final rows = await db.query('payment_allocations', where: 'billId = ?', whereArgs: ['bill-1']);
    expect(rows, hasLength(2));
    expect(rows.fold<double>(0, (sum, row) => sum + (row['amount'] as num).toDouble()), 100);
  });
}