import 'package:flutter_test/flutter_test.dart';
import 'package:shopkeeper_pro/models/bill.dart';

void main() {
  group('Bill calculations', () {
    final items = <BillItem>[
      BillItem(productId: 'tea', productName: 'Tea', quantity: 2, unitPrice: 150),
      BillItem(productId: 'milk', productName: 'Milk', quantity: 1, unitPrice: 120),
    ];

    test('subtotal, discount, tax and grand total are consistent', () {
      final bill = Bill(
        id: 'bill-1',
        date: DateTime(2026, 10, 9),
        items: items,
        discount: 20,
        taxPercent: 17,
      );

      expect(bill.subtotal, 420);
      expect(bill.taxableSubtotal, 400);
      expect(bill.taxAmount, closeTo(68, 0.0001));
      expect(bill.grandTotal, closeTo(468, 0.0001));
    });

    test('refund includes proportional discount and tax', () {
      final bill = Bill(
        id: 'bill-2',
        date: DateTime(2026, 10, 9),
        items: items,
        discount: 42,
        taxPercent: 10,
      );

      // 10% overall discount; return one Tea: 150 * 0.9 * 1.1 = 148.5.
      expect(bill.refundFor(items.first, 1), closeTo(148.5, 0.0001));
    });

    test('refund rejects zero, negative and over-sold quantities', () {
      final bill = Bill(
        id: 'bill-3',
        date: DateTime(2026, 10, 9),
        items: items,
      );

      expect(() => bill.refundFor(items.first, 0), throwsArgumentError);
      expect(() => bill.refundFor(items.first, -1), throwsArgumentError);
      expect(() => bill.refundFor(items.first, 3), throwsArgumentError);
    });

    test('fully discounted bill never has a negative taxable subtotal', () {
      final bill = Bill(
        id: 'bill-4',
        date: DateTime(2026, 10, 9),
        items: items,
        discount: 999,
        taxPercent: 17,
      );

      expect(bill.taxableSubtotal, 0);
      expect(bill.grandTotal, 0);
    });
  });
}
