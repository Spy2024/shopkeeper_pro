import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shopkeeper_pro/providers/inventory_provider.dart';
import 'package:shopkeeper_pro/models/product.dart';
import 'package:shopkeeper_pro/services/db_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async => DBService.instance.resetForTests());
  tearDown(() async => DBService.instance.resetForTests());

  test('CRUD persists product and preserves low-stock threshold', () async {
    final inventory = InventoryProvider();
    await inventory.addProduct(
      name: 'Tea',
      category: 'Grocery',
      stockQuantity: 3,
      costPrice: 100,
      sellingPrice: 150,
      lowStockThreshold: 4,
    );

    expect(inventory.products.single.name, 'Tea');
    expect(inventory.lowOrOutOfStock.single.stockQuantity, 3);

    final product = inventory.products.single;
    await inventory.updateProduct(
      Product(
        id: product.id,
        name: product.name,
        category: product.category,
        stockQuantity: product.stockQuantity,
        costPrice: product.costPrice,
        sellingPrice: 160,
        lowStockThreshold: product.lowStockThreshold,
      ),
    );

    expect(inventory.products.single.sellingPrice, 160);
    expect(inventory.products.single.lowStockThreshold, 4);

    await inventory.deleteProduct(product.id);
    expect(inventory.products, isEmpty);
    expect((await (await DBService.instance.database).query('products')), isEmpty);
  });

  test('deductStock rejects negative result instead of clamping silently', () async {
    final inventory = InventoryProvider();
    await inventory.addProduct(
      name: 'Milk',
      category: 'Dairy',
      stockQuantity: 2,
      costPrice: 60,
      sellingPrice: 90,
    );

    await expectLater(
      inventory.deductStock('Milk', 3),
      throwsA(isA<StateError>()),
    );
    expect(inventory.products.single.stockQuantity, 2);
  });
}
