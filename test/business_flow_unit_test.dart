import 'package:flutter_test/flutter_test.dart';
import 'package:shopkeeper_pro/models/bill.dart';
import 'package:shopkeeper_pro/models/product.dart';
import 'package:shopkeeper_pro/providers/pos_provider.dart';

/// These are domain/unit tests. Live Firebase, multi-device, printer, and
/// Android lifecycle checks must be exercised by dedicated device test plans;
/// these assertions intentionally do not claim to execute those workflows.
void main() {
  group('Billing domain behavior', () {
    test('Bill calculates subtotal, discount, tax, and grand total', () {
      final bill = Bill(
        id: 'bill-unit-1',
        date: DateTime(2026, 10, 20),
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

    test('Bill line items survive map serialization', () {
      final item = BillItem(
        productName: 'Tea',
        quantity: 3,
        unitPrice: 125.5,
      );

      final restored = BillItem.fromMap(item.toMap());

      expect(restored.productName, 'Tea');
      expect(restored.quantity, 3);
      expect(restored.unitPrice, 125.5);
      expect(restored.lineTotal, 376.5);
    });

    test('POS provider computes the cart total from real cart state', () {
      final pos = PosProvider();
      pos.addItem('Tea', 2, 150);
      pos.addItem('Sugar', 1, 120);
      pos.setDiscount(20);
      pos.setTax(17);

      expect(pos.cart, hasLength(2));
      expect(pos.subtotal, 420);
      expect(pos.grandTotal, closeTo(468, 0.0001));
    });

    test('POS provider ignores zero or negative cart entries', () {
      final pos = PosProvider();
      pos.addItem('Tea', 0, 150);
      pos.addItem('Sugar', -1, 120);
      pos.addItem('Milk', 1, -5);

      expect(pos.cart, isEmpty);
      expect(pos.subtotal, 0);
    });
  });

  group('Inventory domain behavior', () {
    test('stock warning state follows the product quantity', () {
      final low = Product(
        id: 'low',
        name: 'Tea',
        category: 'Grocery',
        stockQuantity: 3,
        costPrice: 80,
        sellingPrice: 120,
        lowStockThreshold: 5,
      );
      final normal = Product(
        id: 'normal',
        name: 'Sugar',
        category: 'Grocery',
        stockQuantity: 20,
        costPrice: 50,
        sellingPrice: 70,
        lowStockThreshold: 5,
      );
      final empty = Product(
        id: 'empty',
        name: 'Milk',
        category: 'Dairy',
        stockQuantity: 0,
        costPrice: 40,
        sellingPrice: 60,
        lowStockThreshold: 5,
      );

      expect(low.isLowStock, isTrue);
      expect(normal.isLowStock, isFalse);
      expect(empty.isOutOfStock, isTrue);
    });

    test('product fields survive map serialization', () {
      final product = Product(
        id: 'tea-1',
        name: 'Tea',
        category: 'Grocery',
        stockQuantity: 24,
        costPrice: 80,
        sellingPrice: 120,
        lowStockThreshold: 4,
      );

      final restored = Product.fromMap(product.toMap());

      expect(restored.id, 'tea-1');
      expect(restored.stockQuantity, 24);
      expect(restored.costPrice, 80);
      expect(restored.sellingPrice, 120);
      expect(restored.lowStockThreshold, 4);
    });
  });
}
