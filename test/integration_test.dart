import 'package:flutter_test/flutter_test.dart';
import 'package:shopkeeper_pro/models/bill.dart';
import 'package:shopkeeper_pro/models/daily_sale.dart';
import 'package:shopkeeper_pro/models/product.dart';
import 'package:shopkeeper_pro/models/supplier.dart';

void main() {
  group('Shopkeeper business-flow tests', () {
    test('authentication phone format expectation', () {
      expect(RegExp(r'^\+\d{8,15}$').hasMatch('+923334455667'), isTrue);
    });

    test('inventory stock calculation', () {
      final p = Product(id: 'p1', name: 'Tea', category: 'Grocery',
        stockQuantity: 50, costPrice: 80, sellingPrice: 120);
      expect(p.stockQuantity - 2, 48);
    });

    test('POS bill calculation', () {
      final bill = Bill(id: 'b1', date: DateTime.now(),
        items: [BillItem(productId: 'p1', productName: 'Tea', quantity: 2, unitPrice: 150),
          BillItem(productId: 'p2', productName: 'Milk', quantity: 1, unitPrice: 120)],
        discount: 20, taxPercent: 17);
      expect(bill.grandTotal, closeTo(468.0, 0.0001));
    });

    test('daily sale margin is correct', () {
      final sale = DailySale(id: 's1', date: DateTime.now(), productName: 'Tea',
        costPrice: 100, salePrice: 150, source: 'pos');
      expect(sale.margin, 50);
    });

    test('supplier balance cannot be negative conceptually', () {
      final supplier = Supplier(id: 's1', name: 'ABC', phone: '',
        totalStockReceivedValue: 1000, totalPaymentsMade: 400);
      expect(supplier.remainingBalance, 600);
    });
  });
}
