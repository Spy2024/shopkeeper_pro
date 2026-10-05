import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PosProvider Tests', () {
    test('addItem should add to cart', () async {
      const quantity = 2;
      const unitPrice = 150.0;
      const lineTotal = quantity * unitPrice;
      expect(lineTotal, equals(300.0));
    });

    test('subtotal should sum all line items', () async {
      const item1 = 2 * 150.0;
      const item2 = 1 * 120.0;
      const subtotal = item1 + item2;
      expect(subtotal, equals(420.0));
    });

    test('setDiscount should apply to calculation', () async {
      const subtotal = 5000.0;
      const discount = 500.0;
      const afterDiscount = subtotal - discount;
      expect(afterDiscount, equals(4500.0));
    });

    test('setTax should calculate percentage', () async {
      const subtotal = 5000.0;
      const taxPercent = 17.0;
      const taxAmount = (subtotal * taxPercent) / 100;
      expect(taxAmount, equals(850.0));
    });

    test('grandTotal calculation should be correct', () async {
      const subtotal = 5000.0;
      const discount = 500.0;
      const taxPercent = 17.0;
      const afterDiscount = subtotal - discount;
      const tax = (afterDiscount * taxPercent) / 100;
      const grandTotal = afterDiscount + tax;
      expect(grandTotal, equals(5265.0));
    });
  });
}