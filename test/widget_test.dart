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
    expect(bill.taxableSubtotal, 0);
    expect(bill.grandTotal, 0);
  });
}
