import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shopkeeper_pro/providers/finance_provider.dart';
import 'package:shopkeeper_pro/providers/inventory_provider.dart';
import 'package:shopkeeper_pro/providers/pos_provider.dart';
import 'package:shopkeeper_pro/providers/sales_provider.dart';
import 'package:shopkeeper_pro/services/db_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async => DBService.instance.resetForTests());
  tearDown(() async => DBService.instance.resetForTests());

  test('offline sale persists bill, stock, sales and expense locally', () async {
    final inventory = InventoryProvider();
    final sales = SalesProvider();
    final finance = FinanceProvider();

    await inventory.addProduct(
      name: 'Tea',
      category: 'Grocery',
      stockQuantity: 10,
      costPrice: 100,
      sellingPrice: 150,
    );

    final pos = PosProvider();
    pos.addItem('Tea', 2, 150);
    pos.setDiscount(20);
    pos.setTax(17);
    final bill = await pos.checkout(inventory);

    await sales.load();
    await finance.addExpense('Shop Rent', 1000);

    expect(bill.grandTotal, closeTo(468, 0.0001));
    expect(inventory.products.single.stockQuantity, 8);
    expect(sales.sales.length, 2);
    expect(finance.totalExpensesForMonth(DateTime.now().year, DateTime.now().month), 1000);

    final db = await DBService.instance.database;
    expect((await db.query('bills')).length, 1);
    expect((await db.query('daily_sales')).length, 2);
    expect((await db.query('expenses')).length, 1);
  });

  test('SQLite transaction leaves no partial checkout after failure', () async {
    final inventory = InventoryProvider();
    await inventory.addProduct(
      name: 'Milk',
      category: 'Dairy',
      stockQuantity: 1,
      costPrice: 60,
      sellingPrice: 90,
    );

    final pos = PosProvider();
    pos.addItem('Milk', 1, 90);
    pos.addItem('Milk', 1, 90);

    await expectLater(pos.checkout(inventory), throwsA(isA<StateError>()));

    final db = await DBService.instance.database;
    expect(await db.query('bills'), isEmpty);
    expect(await db.query('bill_items'), isEmpty);
    expect(await db.query('daily_sales'), isEmpty);
    expect((await db.query('products')).single['stockQuantity'], 1);
  });
}
