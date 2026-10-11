import 'package:flutter_test/flutter_test.dart';
import 'package:shopkeeper_pro/providers/pos_provider.dart';

void main() {
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

    test('rejects empty names, non-positive quantities and prices', () {
      expect(() => provider.addItem('  ', 1, 10), throwsArgumentError);
      expect(() => provider.addItem('Tea', 0, 10), throwsArgumentError);
      expect(() => provider.addItem('Tea', -1, 10), throwsArgumentError);
      expect(() => provider.addItem('Tea', 1, 0), throwsArgumentError);
      expect(() => provider.addItem('Tea', 1, -10), throwsArgumentError);
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
    });

    test('tax accepts only percentages from zero through one hundred', () {
      expect(() => provider.setTax(-0.1), throwsArgumentError);
      expect(() => provider.setTax(100.1), throwsArgumentError);

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
}
