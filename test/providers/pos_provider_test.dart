import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shopkeeper_pro/services/db_service.dart';
import 'package:shopkeeper_pro/models/bill.dart';
import 'package:shopkeeper_pro/models/product.dart';
import 'package:shopkeeper_pro/models/mobile_device.dart';
import 'package:shopkeeper_pro/providers/pos_provider.dart';

void main() {
  group('Persisted bill reconstruction', () {
    test('preserves branch attribution when loading bill history', () {
      final bill = billFromDatabaseRow(
        {
          'id': 'bill-branch',
          'date': DateTime(2026, 10, 16).toIso8601String(),
          'customerName': 'Ayesha',
          'branchId': 'branch-lahore',
          'discount': 0.0,
          'taxPercent': 0.0,
        },
        [BillItem(productName: 'Manual item', quantity: 1, unitPrice: 50)],
      );

      expect(bill.branchId, 'branch-lahore');
      expect(bill.customerName, 'Ayesha');
      expect(bill.grandTotal, 50);
    });
  });

  group('PosProvider cart and totals', () {
    late PosProvider provider;

    setUp(() {
      provider = PosProvider();
    });

    test('adds a valid item and calculates its line total', () {
      provider.addItem('Tea', 2, 150, productId: 'tea-1');

      expect(provider.cart, hasLength(1));
      expect(provider.cart.single.productName, 'Tea');
      expect(provider.cart.single.productId, 'tea-1');
      expect(provider.cart.single.lineTotal, 300);
      expect(provider.subtotal, 300);
      expect(provider.grandTotal, 300);
    });

    test('combines repeated items with the same product id', () {
      provider.addItem('Tea', 2, 150, productId: 'tea-1');
      provider.addItem('Tea', 3, 150, productId: 'tea-1');

      expect(provider.cart, hasLength(1));
      expect(provider.cart.single.quantity, 5);
      expect(provider.subtotal, 750);
    });
    test('adds an individually tracked handset with exact IMEI and quantity one', () {
      final device = MobileDevice(
        id: 'device-1',
        deviceType: 'used',
        brand: 'Samsung',
        model: 'Galaxy S22',
        imei1: '351234567890123',
        status: 'in_stock',
        purchasePrice: 42000,
        repairCost: 1000,
        sellingPrice: 49000,
        createdAt: DateTime(2026, 10, 16),
        updatedAt: DateTime(2026, 10, 16),
      );

      provider.addMobileDevice(device);

      expect(provider.cart, hasLength(1));
      expect(provider.cart.single.mobileDeviceId, 'device-1');
      expect(provider.cart.single.mobileImei, '351234567890123');
      expect(provider.cart.single.quantity, 1);
      expect(provider.cart.single.unitPrice, 49000);
      expect(() => provider.addMobileDevice(device), throwsStateError);
    });

    test('refuses a handset that is not sale-ready', () {
      final device = MobileDevice(
        id: 'device-inspection',
        deviceType: 'used',
        brand: 'Samsung',
        model: 'Galaxy S22',
        imei1: '351234567890124',
        status: 'inspection_pending',
        createdAt: DateTime(2026, 10, 16),
        updatedAt: DateTime(2026, 10, 16),
      );
      expect(() => provider.addMobileDevice(device), throwsStateError);
      expect(provider.cart, isEmpty);
    });

    test('rejects empty names, non-positive quantities and prices', () {
      expect(() => provider.addItem('  ', 1, 10), throwsArgumentError);
      expect(() => provider.addItem('Tea', 0, 10), throwsArgumentError);
      expect(() => provider.addItem('Tea', -1, 10), throwsArgumentError);
      expect(() => provider.addItem('Tea', 1, 0), throwsArgumentError);
      expect(() => provider.addItem('Tea', 1, -10), throwsArgumentError);
      expect(() => provider.addItem('Tea', 1, double.nan), throwsArgumentError);
      expect(() => provider.addItem('Tea', 1, double.infinity), throwsArgumentError);
      expect(() => provider.addItem('Tea', 2, double.maxFinite), throwsArgumentError);
      expect(provider.cart, isEmpty);
    });

    test('discount, tax and grand total use the discounted subtotal', () {
      provider.addItem('Tea', 2, 150, productId: 'tea-1');
      provider.addItem('Milk', 1, 120, productId: 'milk-1');

      provider.setDiscount(20);
      provider.setTax(17);

      expect(provider.subtotal, 420);
      expect(provider.taxableSubtotal, 400);
      expect(provider.taxAmount, closeTo(68, 0.0001));
      expect(provider.grandTotal, closeTo(468, 0.0001));
    });

    test('discount is capped at subtotal and cannot be negative', () {
      provider.addItem('Tea', 1, 100, productId: 'tea-1');

      provider.setDiscount(500);
      expect(provider.discount, 100);
      expect(provider.grandTotal, 0);
      expect(() => provider.setDiscount(-1), throwsArgumentError);
      expect(() => provider.setDiscount(double.nan), throwsArgumentError);
      expect(() => provider.setDiscount(double.infinity), throwsArgumentError);
    });

    test('tax accepts only percentages from zero through one hundred', () {
      expect(() => provider.setTax(-0.1), throwsArgumentError);
      expect(() => provider.setTax(100.1), throwsArgumentError);
      expect(() => provider.setTax(double.nan), throwsArgumentError);
      expect(() => provider.setTax(double.infinity), throwsArgumentError);

      provider.setTax(17);
      expect(provider.taxPercent, 17);
    });

    test('customer name is trimmed and blank values clear it', () {
      provider.setCustomerName('  Ayesha Khan  ');
      expect(provider.customerName, 'Ayesha Khan');

      provider.setCustomerName('   ');
      expect(provider.customerName, isNull);
    });

    test('removeItem ignores invalid indices and removes valid items', () {
      provider.addItem('Tea', 1, 100, productId: 'tea-1');
      provider.removeItem(-1);
      provider.removeItem(1);
      expect(provider.cart, hasLength(1));

      provider.removeItem(0);
      expect(provider.cart, isEmpty);
    });

    test('clearCart resets items, totals, tax, discount and customer', () {
      provider.addItem('Tea', 2, 150, productId: 'tea-1');
      provider.setDiscount(10);
      provider.setTax(17);
      provider.setCustomerName('Ayesha');

      provider.clearCart();

      expect(provider.cart, isEmpty);
      expect(provider.subtotal, 0);
      expect(provider.discount, 0);
      expect(provider.taxPercent, 0);
      expect(provider.customerName, isNull);
      expect(provider.grandTotal, 0);
    });
  });
  group('Manual bill-only return identity', () {
    test('uses a stable bill-scoped key without a catalogue product ID', () {
      final bill = Bill(
        id: 'manual-return-bill',
        date: DateTime(2026, 10, 16),
        items: [
          BillItem(productName: '  Gift wrap  ', quantity: 2, unitPrice: 25),
        ],
      );
      final item = bill.items.single;

      expect(manualBillItemReturnKey(bill, item),
          'manual:manual-return-bill:gift wrap:25.0000');
      expect(manualBillItemReturnKey(bill, item),
          manualBillItemReturnKey(bill, item));
    });

    test('separates manual return keys for different bills and prices', () {
      final firstBill = Bill(
        id: 'bill-a',
        date: DateTime(2026, 10, 16),
        items: [BillItem(productName: 'Gift wrap', quantity: 1, unitPrice: 25)],
      );
      final secondBill = Bill(
        id: 'bill-b',
        date: DateTime(2026, 10, 16),
        items: [BillItem(productName: 'Gift wrap', quantity: 1, unitPrice: 30)],
      );

      expect(manualBillItemReturnKey(firstBill, firstBill.items.single),
          isNot(manualBillItemReturnKey(secondBill, secondBill.items.single)));
    });
  });

  group('Return line quantity isolation', () {
    final product = Product(
      id: 'tea-1',
      name: 'Tea',
      category: 'Grocery',
      stockQuantity: 0,
      costPrice: 50,
      sellingPrice: 200,
    );

    test('does not combine sold quantities from different price lines', () {
      final cheaperLine = BillItem(
        productId: 'tea-1',
        productName: 'Tea',
        quantity: 3,
        unitPrice: 100,
      );
      final expensiveLine = BillItem(
        productId: 'tea-1',
        productName: 'Tea',
        quantity: 1,
        unitPrice: 200,
      );
      final bill = Bill(
        id: 'bill-returns',
        date: DateTime(2026, 10, 11),
        items: [cheaperLine, expensiveLine],
      );

      expect(
        soldQuantityForReturnLine(bill: bill, item: expensiveLine, product: product),
        1,
      );
      expect(
        soldQuantityForReturnLine(bill: bill, item: cheaperLine, product: product),
        3,
      );
    });

    test('combines identical product and unit-price lines', () {
      final first = BillItem(
        productId: 'tea-1',
        productName: 'Tea',
        quantity: 2,
        unitPrice: 150,
      );
      final second = BillItem(
        productId: 'tea-1',
        productName: 'Tea',
        quantity: 4,
        unitPrice: 150,
      );
      final bill = Bill(
        id: 'bill-same-price',
        date: DateTime(2026, 10, 11),
        items: [first, second],
      );

      expect(
        soldQuantityForReturnLine(bill: bill, item: first, product: product),
        6,
      );
    });
  });

  group('Bill item inventory identity', () {
    final products = <Product>[
      Product(id: 'tea-old', name: 'Tea', category: 'Grocery',
          stockQuantity: 10, costPrice: 50, sellingPrice: 100),
      Product(id: 'tea-new', name: 'Tea', category: 'Grocery',
          stockQuantity: 20, costPrice: 60, sellingPrice: 120),
    ];

    test('does not resolve a stale product ID to another same-name product', () {
      final item = BillItem(
        productId: 'deleted-tea-id',
        productName: 'Tea',
        quantity: 1,
        unitPrice: 100,
      );

      expect(resolveProductForBillItem(item, products), isNull);
    });

    test('uses the exact product ID when names are duplicated', () {
      final item = BillItem(
        productId: 'tea-new',
        productName: 'Tea',
        quantity: 1,
        unitPrice: 120,
      );

      expect(resolveProductForBillItem(item, products)?.id, 'tea-new');
    });

    test('retains case-insensitive name lookup for legacy items without IDs', () {
      final item = BillItem(
        productName: '  tEa  ',
        quantity: 1,
        unitPrice: 100,
      );

      expect(resolveProductForBillItem(item, products)?.id, 'tea-old');
    });

    test('does not treat a manual return line as inventory by matching name', () {
      final manualItem = BillItem(
        productName: 'Tea',
        quantity: 1,
        unitPrice: 100,
      );

      expect(resolveProductForReturn(manualItem, products), isNull);
    });

    test('resolves a catalogue return only by its explicit product ID', () {
      final catalogueItem = BillItem(
        productId: 'tea-new',
        productName: 'Tea',
        quantity: 1,
        unitPrice: 120,
      );

      expect(resolveProductForReturn(catalogueItem, products)?.id, 'tea-new');
    });
  });


  group('Bill History SQLite restart round-trip', () {
    const testUserId = 'bill-history-restart-test-user';
    late PosProvider historyProvider;

    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      await databaseFactoryFfi.setDatabasesPath('/tmp/shopkeeper_pro_bill_history_test');
    });

    setUp(() async {
      await DBService.instance.clearActiveUser();
      await DBService.instance.configureForUser(testUserId);
      historyProvider = PosProvider();
      final db = await DBService.instance.database;
      await db.delete('bills');
      // Bill items cascade-delete with their parent when foreign keys are enabled.
    });

    tearDown(() async {
      await DBService.instance.clearActiveUser();
    });

    test('reloads saved bill and items after closing and reopening SQLite', () async {
      final db = await DBService.instance.database;
      final bill = Bill(
        id: 'restart-round-trip-bill',
        date: DateTime(2026, 10, 20, 10, 30),
        customerName: 'Restart Customer',
        customerPhone: '03001234567',
        items: [
          BillItem(productId: 'tea-1', productName: 'Tea', quantity: 2, unitPrice: 150),
          BillItem(productName: 'Gift wrap', quantity: 1, unitPrice: 25),
        ],
        discount: 10,
        taxPercent: 5,
      );

      await db.transaction((txn) async {
        await txn.insert('bills', bill.toMap());
        for (final item in bill.items) {
          await txn.insert('bill_items', {
            ...item.toMap(),
            'billId': bill.id,
            'cloudId': 'cloud-${bill.items.indexOf(item)}',
          });
        }
      });

      await DBService.instance.clearActiveUser();
      await DBService.instance.configureForUser(testUserId);
      await historyProvider.loadHistory();

      expect(historyProvider.savedBills, hasLength(1));
      final restored = historyProvider.savedBills.single;
      expect(restored.id, bill.id);
      expect(restored.customerName, 'Restart Customer');
      expect(restored.customerPhone, '03001234567');
      expect(restored.items, hasLength(2));
      expect(restored.items[0].productId, 'tea-1');
      expect(restored.items[0].quantity, 2);
      expect(restored.items[1].productName, 'Gift wrap');
      expect(restored.grandTotal, closeTo(330.75, 0.001));
    });
  });

}
