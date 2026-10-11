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

    test('bill defensively copies its item list', () {
      final mutableItems = <BillItem>[items.first];
      final bill = Bill(id: 'bill-copy', date: DateTime(2026), items: mutableItems);
      mutableItems.clear();
      expect(bill.items, hasLength(1));
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
      final bill = Bill(id: 'bill-3', date: DateTime(2026, 10, 9), items: items);
      expect(() => bill.refundFor(items.first, 0), throwsArgumentError);
      expect(() => bill.refundFor(items.first, -1), throwsArgumentError);
      expect(() => bill.refundFor(items.first, 3), throwsArgumentError);
    });

    test('refund rejects an item not present on this bill', () {
      final bill = Bill(id: 'bill-foreign', date: DateTime(2026), items: [items.first]);
      final foreign = BillItem(productId: 'other', productName: 'Other', quantity: 1, unitPrice: 20);
      expect(() => bill.refundFor(foreign, 1), throwsArgumentError);
    });

    test('bill item rejects invalid quantity, name and price', () {
      expect(() => BillItem(productName: 'Tea', quantity: 0, unitPrice: 1), throwsArgumentError);
      expect(() => BillItem(productName: ' ', quantity: 1, unitPrice: 1), throwsArgumentError);
      expect(() => BillItem(productName: 'Tea', quantity: 1, unitPrice: double.nan), throwsArgumentError);
      expect(() => BillItem(productName: 'Tea', quantity: 1, unitPrice: -1), throwsArgumentError);
    });

    test('bill rejects invalid tax and discount values', () {
      expect(() => Bill(id: 'bad-tax', date: DateTime(2026), items: items, taxPercent: 101), throwsArgumentError);
      expect(() => Bill(id: 'bad-discount', date: DateTime(2026), items: items, discount: -1), throwsArgumentError);
      expect(() => Bill(id: ' ', date: DateTime(2026), items: items), throwsArgumentError);
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
      expect(bill.refundFor(items.first, 1), 0);
    });
  });
}
