import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shopkeeper_pro/models/bill.dart';
import 'package:shopkeeper_pro/models/product.dart';
import 'package:shopkeeper_pro/providers/inventory_provider.dart';
import 'package:shopkeeper_pro/providers/pos_provider.dart';
import 'package:shopkeeper_pro/services/db_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await DBService.instance.resetForTests();
  });

  tearDown(() async {
    await DBService.instance.resetForTests();
  });

  group('POS calculations', () {
    test('calculates subtotal, capped discount, tax and total', () {
      final pos = PosProvider();
      pos.addItem('Tea', 2, 150);
      pos.addItem('Sugar', 1, 120);
      pos.setDiscount(500);
      pos.setTax(17);

      expect(pos.subtotal, 420);
      expect(pos.effectiveDiscount, 420);
      expect(pos.taxAmount, 0);
      expect(pos.grandTotal, 0);
    });

    test('normal discount and tax produce expected total', () {
      final bill = Bill(
        id: 'b1',
        date: DateTime(2026, 10, 1),
        items: [
          BillItem(productName: 'Tea', quantity: 2, unitPrice: 150),
          BillItem(productName: 'Sugar', quantity: 1, unitPrice: 120),
        ],
        discount: 20,
        taxPercent: 17,
      );

      expect(bill.subtotal, 420);
      expect(bill.taxAmount, closeTo(68, 0.0001));
      expect(bill.grandTotal, closeTo(468, 0.0001));
    });
  });

  group('POS SQLite checkout', () {
    test('checkout atomically saves bill, sales and stock', () async {
      final inventory = InventoryProvider();
      await inventory.addProduct(
        name: 'Tea',
        category: 'Grocery',
        stockQuantity: 5,
        costPrice: 100,
        sellingPrice: 150,
      );

      final pos = PosProvider();
      pos.addItem('Tea', 2, 150);
      final bill = await pos.checkout(inventory);

      final db = await DBService.instance.database;
      expect((await db.query('bills')).length, 1);
      expect((await db.query('bill_items')).length, 1);
      expect((await db.query('daily_sales')).length, 2);

      final product = (await db.query('products')).single;
      expect(product['stockQuantity'], 3);
      expect(bill.grandTotal, 300);
    });

    test('checkout rolls back when a later stock deduction fails', () async {
      final inventory = InventoryProvider();
      await inventory.addProduct(
        name: 'Tea',
        category: 'Grocery',
        stockQuantity: 2,
        costPrice: 100,
        sellingPrice: 150,
      );

      final pos = PosProvider();
      pos.addItem('Tea', 2, 150);
      pos.addItem('Tea', 1, 150);

      await expectLater(
        pos.checkout(inventory),
        throwsA(isA<StateError>()),
      );

      final db = await DBService.instance.database;
      expect((await db.query('bills')), isEmpty);
      expect((await db.query('bill_items')), isEmpty);
      expect((await db.query('daily_sales')), isEmpty);
      expect((await db.query('products')).single['stockQuantity'], 2);
    });
  }

  test('Product margin is derived from selling minus cost', () {
    final product = Product(
      id: 'p1',
      name: 'Tea',
      category: 'Grocery',
      stockQuantity: 10,
      costPrice: 100,
      sellingPrice: 150,
    );
    expect(product.margin, 50);
    expect(product.isLowStock, false);
  });
}
