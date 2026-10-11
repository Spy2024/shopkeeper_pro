import 'package:flutter_test/flutter_test.dart';
import 'package:shopkeeper_pro/models/bill.dart';

void main() {
  group('Bill return validation and refund calculation', () {
    late Bill bill;
    late BillItem tea;

    setUp(() {
      tea = BillItem(
        productId: 'tea-1',
        productName: 'Tea',
        quantity: 2,
        unitPrice: 150,
      );
      bill = Bill(
        id: 'bill-1',
        date: DateTime(2026, 10, 11),
        items: [
          tea,
          BillItem(
            productId: 'milk-1',
            productName: 'Milk',
            quantity: 1,
            unitPrice: 120,
          ),
        ],
        discount: 42,
        taxPercent: 17,
      );
    });

    test('refund includes proportional bill discount and tax', () {
      // Subtotal is 420; discount is 10%, so tea's discounted unit price is 135.
      // Tax of 17% makes the refund 157.95 per unit.
      expect(bill.refundFor(tea, 1), closeTo(157.95, 0.0001));
      expect(bill.refundFor(tea, 2), closeTo(315.90, 0.0001));
    });

    test('rejects a zero or negative return quantity', () {
      expect(() => bill.refundFor(tea, 0), throwsArgumentError);
      expect(() => bill.refundFor(tea, -1), throwsArgumentError);
    });

    test('rejects return quantity greater than this bill line quantity', () {
      expect(() => bill.refundFor(tea, 3), throwsArgumentError);
    });

    test('rejects a product line that does not belong to this bill', () {
      final unrelated = BillItem(
        productId: 'other-tea',
        productName: 'Tea',
        quantity: 2,
        unitPrice: 150,
      );
      expect(() => bill.refundFor(unrelated, 1), throwsArgumentError);
    });
  });
}
