import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shopkeeper_pro/services/db_service.dart';
import 'package:shopkeeper_pro/services/business_operations_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final operations = BusinessOperationsService.instance;
  final dbService = DBService.instance;
  String userId() => 'business_test_${DateTime.now().microsecondsSinceEpoch}';

  tearDown(() async {
    await dbService.clearActiveUser();
  });

  test('each authenticated user receives a separate SQLite database', () async {
    final firstUser = userId();
    await dbService.configureForUser(firstUser);
    final firstDb = await dbService.database;
    await firstDb.insert('products', {
      'id': 'private-product',
      'name': 'Private tea',
      'category': 'grocery',
      'stockQuantity': 9,
      'costPrice': 1,
      'sellingPrice': 2,
      'lowStockThreshold': 2,
    });

    await dbService.configureForUser(userId());
    final secondDb = await dbService.database;
    expect(await secondDb.query('products', where: 'id = ?', whereArgs: ['private-product']), isEmpty);

    await dbService.configureForUser(firstUser);
    final restoredDb = await dbService.database;
    expect(await restoredDb.query('products', where: 'id = ?', whereArgs: ['private-product']), hasLength(1));
  });

  test('customer ledger calculates outstanding balance', () async {
    await dbService.configureForUser(userId());
    final customerId = await operations.addCustomer(name: 'Test Customer');
    await operations.recordCustomerLedgerEntry(
      customerId: customerId, type: 'credit', amount: 1250, note: 'Sale on credit');
    await operations.recordCustomerLedgerEntry(
      customerId: customerId, type: 'payment', amount: 400, note: 'Cash received');
    expect(await operations.customerBalance(customerId), 850);
  });

  test('split payment rejects mismatched total and stores valid tenders', () async {
    await dbService.configureForUser(userId());
    final db = await dbService.database;
    await db.insert('bills', {
      'id': 'bill-split', 'date': DateTime.now().toIso8601String(),
      'customerName': null, 'discount': 0, 'taxPercent': 0,
    });

    expect(
      () => operations.recordSplitPayment(
        billId: 'bill-split',
        billTotal: 1000,
        payments: const [PaymentLine(method: 'cash', amount: 500)],
      ),
      throwsStateError,
    );
    await operations.recordSplitPayment(
      billId: 'bill-split',
      billTotal: 1000,
      payments: const [
        PaymentLine(method: 'cash', amount: 400),
        PaymentLine(method: 'card', amount: 600),
      ],
    );
    expect(await db.query('payments', where: 'billId = ?', whereArgs: ['bill-split']), hasLength(2));
  });

  test('return restores stock atomically and cannot return more than sold', () async {
    await dbService.configureForUser(userId());
    final db = await dbService.database;
    await db.insert('products', {
      'id': 'product-1', 'name': 'Rice', 'category': 'grocery',
      'stockQuantity': 3, 'costPrice': 10, 'sellingPrice': 15, 'lowStockThreshold': 2,
    });
    await db.insert('bills', {
      'id': 'bill-return', 'date': DateTime.now().toIso8601String(),
      'customerName': 'Test Customer', 'discount': 0, 'taxPercent': 0,
    });
    await db.insert('bill_items', {
      'billId': 'bill-return', 'productName': 'Rice', 'quantity': 2, 'unitPrice': 15,
    });

    await operations.processReturn(
      billId: 'bill-return',
      items: const [ReturnLine(productId: 'product-1', productName: 'Rice', quantity: 1, unitPrice: 15)],
      refundAmount: 15,
      customerName: 'Test Customer',
    );
    final stock = await db.query('products', columns: ['stockQuantity'], where: 'id = ?', whereArgs: ['product-1']);
    expect(stock.single['stockQuantity'], 4);

    await expectLater(
      operations.processReturn(
        billId: 'bill-return',
        items: const [ReturnLine(productId: 'product-1', productName: 'Rice', quantity: 2, unitPrice: 15)],
        refundAmount: 30,
      ),
      throwsStateError,
    );
    final returns = await db.query('returns', where: 'billId = ?', whereArgs: ['bill-return']);
    expect(returns, hasLength(1));
  });

  test('branch report combines stock units and cash in/out', () async {
    await dbService.configureForUser(userId());
    final db = await dbService.database;
    final branchId = await operations.createBranch(name: 'Main Branch');
    await db.insert('products', {
      'id': 'branch-product', 'name': 'Sugar', 'category': 'grocery',
      'stockQuantity': 30, 'costPrice': 1, 'sellingPrice': 2, 'lowStockThreshold': 5,
    });
    await operations.setBranchStock(branchId: branchId, productId: 'branch-product', quantity: 24);
    await operations.recordBranchCash(branchId: branchId, type: 'in', amount: 5000);
    await operations.recordBranchCash(branchId: branchId, type: 'out', amount: 750);

    final report = await operations.branchReport(branchId);
    expect(report['stockUnits'], 24);
    expect(report['cashBalance'], 4250);
  });
}
