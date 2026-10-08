import 'package:flutter_test/flutter_test.dart';
import 'package:shopkeeper_pro/models/bill.dart';
import 'package:shopkeeper_pro/models/product.dart';

void main() {
  test('Product margin is calculated correctly', () {
    final product = Product(id: 'p1', name: 'Tea', category: 'Grocery',
      stockQuantity: 10, costPrice: 80, sellingPrice: 100);
    expect(product.margin, 20);
    expect(product.isLowStock, isFalse);
  });

  test('Bill totals never produce negative taxable subtotal', () {
    final bill = Bill(id: 'b1', date: DateTime(2026, 10, 6),
      items: [BillItem(productId: 'p1', productName: 'Tea', quantity: 2, unitPrice: 100)],
      discount: 500, taxPercent: 17);
    expect(bill.subtotal, 200);
    expect(bill.taxableSubtotal, 0);
    expect(bill.taxAmount, 0);
    expect(bill.grandTotal, 0);
  });

  test('Bill calculates discount and tax on discounted subtotal', () {
    final bill = Bill(id: 'b2', date: DateTime(2026, 10, 6),
      items: [
        BillItem(productId: 'p1', productName: 'Tea', quantity: 2, unitPrice: 100),
        BillItem(productId: 'p2', productName: 'Sugar', quantity: 1, unitPrice: 50),
      ],
      discount: 25, taxPercent: 10);
    expect(bill.subtotal, 250);
    expect(bill.taxableSubtotal, 225);
    expect(bill.taxAmount, 22.5);
    expect(bill.grandTotal, 247.5);
  });

  test('Bill item keeps inventory ID when serialized', () {
    final item = BillItem(productId: 'inventory-123',
      productName: 'Tea', quantity: 3, unitPrice: 95);
    final restored = BillItem.fromMap(item.toMap());
    expect(restored.productId, 'inventory-123');
    expect(restored.productName, 'Tea');
    expect(restored.lineTotal, 285);
  });
}
