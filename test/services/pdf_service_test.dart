import 'package:flutter_test/flutter_test.dart';
import 'package:shopkeeper_pro/models/bill.dart';

void main() {
  test('invoice data contains all financial components', () {
    final bill = Bill(
      id: 'bill-12345678',
      date: DateTime(2026, 10, 1, 15, 16),
      customerName: 'Ahmed',
      items: [
        BillItem(productName: 'Tea', quantity: 2, unitPrice: 150),
        BillItem(productName: 'Sugar', quantity: 1, unitPrice: 120),
      ],
      discount: 20,
      taxPercent: 17,
    );

    expect(bill.subtotal, 420);
    expect(bill.effectiveDiscount, 20);
    expect(bill.taxAmount, closeTo(68, 0.0001));
    expect(bill.grandTotal, closeTo(468, 0.0001));
  });

  test('invoice serialization keeps shop-independent bill fields and items', () {
    final bill = Bill(
      id: 'b1',
      date: DateTime(2026, 10, 1),
      items: [BillItem(productName: 'Milk', quantity: 1, unitPrice: 90)],
    );

    final sync = bill.toSyncMap();
    expect(sync['id'], 'b1');
    expect(sync['items'], isA<List<dynamic>>());
    expect((sync['items'] as List).single['productName'], 'Milk');
  });
}
