import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shopkeeper_pro/providers/inventory_provider.dart';
import 'package:shopkeeper_pro/providers/pos_provider.dart';
import 'package:shopkeeper_pro/services/db_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final dbService = DBService.instance;
  late InventoryProvider inventory;
  late PosProvider pos;
  late String uid;

  setUp(() async {
    uid = 'pos_test_${DateTime.now().microsecondsSinceEpoch}';
    await dbService.configureForUser(uid);
    inventory = InventoryProvider();
    pos = PosProvider();
  });

  tearDown(() async {
    await dbService.clearActiveUser();
    inventory.dispose();
    pos.dispose();
  });

  test('checkout saves bill and stock atomically and history survives database restart', () async {
    await inventory.addProduct(
      name: 'Tea', category: 'grocery', stockQuantity: 10,
      costPrice: 100, sellingPrice: 150,
    );
    pos.addItem('Tea', 2, 150);
    pos.setCustomerName('Restart Customer');

    final bill = await pos.checkout(inventory);
    expect(bill.grandTotal, 300);

    var db = await dbService.database;
    expect(await db.query('bills', where: 'id = ?', whereArgs: [bill.id]), hasLength(1));
    expect(await db.query('bill_items', where: 'billId = ?', whereArgs: [bill.id]), hasLength(1));
    expect((await db.query('products')).single['stockQuantity'], 8);

    await dbService.clearActiveUser();
    await dbService.configureForUser(uid);
    db = await dbService.database;
    final reloaded = PosProvider();
    await reloaded.loadHistory();

    expect(reloaded.savedBills, hasLength(1));
    expect(reloaded.savedBills.single.id, bill.id);
    expect(reloaded.savedBills.single.customerName, 'Restart Customer');
    expect(reloaded.savedBills.single.items.single.quantity, 2);
    expect((await db.query('products')).single['stockQuantity'], 8);
    reloaded.dispose();
  });

  test('duplicate cart lines cannot oversell and failed checkout writes no bill', () async {
    await inventory.addProduct(
      name: 'Sugar', category: 'grocery', stockQuantity: 3,
      costPrice: 50, sellingPrice: 80,
    );
    pos.addItem('Sugar', 2, 80);
    pos.addItem('Sugar', 2, 80);

    await expectLater(pos.checkout(inventory), throwsStateError);
    final db = await dbService.database;
    expect(await db.query('bills'), isEmpty);
    expect((await db.query('products')).single['stockQuantity'], 3);
  });

  test('split tender rows are committed with the bill', () async {
    await inventory.addProduct(
      name: 'Milk', category: 'grocery', stockQuantity: 5,
      costPrice: 60, sellingPrice: 100,
    );
    pos.addItem('Milk', 2, 100);
    final bill = await pos.checkout(inventory, payments: const [
      // Two tenders sum to the persisted bill total.
      PaymentLine(method: 'cash', amount: 125),
      PaymentLine(method: 'card_or_bank', amount: 75),
    ]);
    final db = await dbService.database;
    final payments = await db.query('payments', where: 'billId = ?', whereArgs: [bill.id]);
    expect(payments, hasLength(2));
    expect(payments.fold<double>(0, (sum, row) => sum + (row['amount'] as num).toDouble()), 200);
  });
}
