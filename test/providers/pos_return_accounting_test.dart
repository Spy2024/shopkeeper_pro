import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shopkeeper_pro/models/bill.dart';
import 'package:shopkeeper_pro/providers/inventory_provider.dart';
import 'package:shopkeeper_pro/providers/pos_provider.dart';
import 'package:shopkeeper_pro/services/branch_accounting_service.dart';
import 'package:shopkeeper_pro/services/db_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var userId = '';
  late InventoryProvider inventory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    userId = 'return-accounting-${DateTime.now().microsecondsSinceEpoch}';
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
    await db.insert('customers', {
      'id': 'customer-1',
      'name': 'Ayesha',
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

  Future<Bill> createBill(String method) async {
    final pos = PosProvider();
    pos.addItem('Tea', 1, 100, productId: 'product-1');
    return pos.checkout(
      inventory,
      branchId: 'branch-1',
      customerId: method == 'credit' ? 'customer-1' : null,
      paymentAllocations: [PaymentAllocationInput(method: method, amount: 100)],
    );
  }

  test('credit refund reverses customer balance and restores stock atomically', () async {
    final bill = await createBill('credit');
    expect(bill.customerId, 'customer-1');
    final refund = await PosProvider().returnItem(
      bill: bill,
      item: bill.items.single,
      quantity: 1,
      reason: 'Customer returned item',
      inventory: inventory,
      refundMethod: 'credit',
    );

    expect(refund, 100);
    expect(await BranchAccountingService.instance.customerBalance('customer-1'), 0);
    final db = await DBService.instance.database;
    final returnRows = await db.query('bill_returns', where: 'billId = ?', whereArgs: [bill.id]);
    expect(returnRows.single['refundMethod'], 'credit');
    expect(await db.query('branch_cash_transactions', where: 'type = ?', whereArgs: ['refund']), isEmpty);
    expect((await db.query('products', where: 'id = ?', whereArgs: ['product-1'])).single['stockQuantity'], 5);
    expect((await db.query('branch_stock', where: 'branchId = ?', whereArgs: ['branch-1'])).single['quantity'], 5);
  });

  test('cash refund is recorded in branch cash and restores stock', () async {
    final bill = await createBill('cash');
    await PosProvider().returnItem(
      bill: bill,
      item: bill.items.single,
      quantity: 1,
      reason: 'Damaged item',
      inventory: inventory,
      refundMethod: 'cash',
    );

    final db = await DBService.instance.database;
    final refunds = await db.query(
      'branch_cash_transactions',
      where: 'branchId = ? AND type = ?',
      whereArgs: ['branch-1', 'refund'],
    );
    expect(refunds, hasLength(1));
    expect((refunds.single['amount'] as num).toDouble(), 100);
    expect((await db.query('bill_returns', where: 'billId = ?', whereArgs: [bill.id])).single['refundMethod'], 'cash');
  });

  test('credit refund requires a customer attached to the original bill', () async {
    final bill = Bill(
      id: 'manual-bill',
      date: DateTime.now(),
      items: [BillItem(productName: 'Manual item', quantity: 1, unitPrice: 10)],
    );
    await expectLater(
      PosProvider().returnItem(
        bill: bill,
        item: bill.items.single,
        quantity: 1,
        reason: 'Test',
        inventory: inventory,
        refundMethod: 'credit',
      ),
      throwsA(isA<StateError>()),
    );
  });
}
