import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shopkeeper_pro/models/product.dart';
import 'package:shopkeeper_pro/providers/branch_provider.dart';
import 'package:shopkeeper_pro/providers/inventory_provider.dart';
import 'package:shopkeeper_pro/services/db_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String userId;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    userId = 'inventory-${DateTime.now().microsecondsSinceEpoch}';
    await DBService.instance.clearActiveUser();
    await DBService.instance.configureForUser(userId);
  });

  tearDown(() async {
    if (DBService.instance.activeUserId == userId) {
      await DBService.instance.deleteActiveUserDatabase(userId);
    }
  });

  test('low stock classification is correct', () {
    final low = Product(id: '1', name: 'Tea', category: 'Grocery',
      stockQuantity: 3, costPrice: 50, sellingPrice: 70, lowStockThreshold: 5);
    final normal = Product(id: '2', name: 'Sugar', category: 'Grocery',
      stockQuantity: 20, costPrice: 50, sellingPrice: 70, lowStockThreshold: 5);
    final out = Product(id: '3', name: 'Milk', category: 'Grocery',
      stockQuantity: 0, costPrice: 50, sellingPrice: 70, lowStockThreshold: 5);
    expect(low.isLowStock, isTrue);
    expect(normal.isLowStock, isFalse);
    expect(out.isOutOfStock, isTrue);
  });

  test('initial product stock is allocated to the only active branch', () async {
    final branches = BranchProvider();
    final branch = await branches.saveBranch(name: 'Main Store', code: 'MAIN');
    final inventory = InventoryProvider();

    await inventory.addProduct(
      name: 'Tea',
      category: 'Grocery',
      stockQuantity: 12,
      costPrice: 80,
      sellingPrice: 120,
    );

    final db = await DBService.instance.database;
    final allocations = await db.query('branch_stock');
    expect(allocations, hasLength(1));
    expect(allocations.single['branchId'], branch.id);
    expect(allocations.single['productId'], inventory.products.single.id);
    expect(allocations.single['quantity'], 12);
  });

  test('multi-branch product stock is not silently assigned to one branch', () async {
    final branches = BranchProvider();
    await branches.saveBranch(name: 'Main Store', code: 'MAIN');
    await branches.saveBranch(name: 'Second Store', code: 'SECOND');
    final inventory = InventoryProvider();

    await inventory.addProduct(
      name: 'Sugar',
      category: 'Grocery',
      stockQuantity: 20,
      costPrice: 50,
      sellingPrice: 70,
    );

    final db = await DBService.instance.database;
    expect(await db.query('branch_stock'), isEmpty);
  });
}
