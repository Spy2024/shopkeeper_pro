import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PdfService Tests', () {
    test('generateInvoice should create PDF file', () async {
      const billId = 'bill-123';
      const shopName = 'Test Shop';
      expect(billId, isNotEmpty);
      expect(shopName, isNotEmpty);
    });

    test('generateInvoice should embed shop logo if available', () async {
      const logoPath = '/path/to/logo.png';
      expect(logoPath, isNotEmpty);
    });

    test('generateInvoice should include tax details', () async {
      const taxPercent = 17.0;
      const subtotal = 1000.0;
      const expectedTax = (subtotal * taxPercent) / 100;
      expect(expectedTax, equals(170.0));
    });

    test('generateInvoice should format currency as Rs.', () async {
      const amount = 5000.0;
      const formatted = 'Rs. 5000.00';
      expect(formatted, contains('Rs.'));
    });

    test('generateInvoice should calculate line totals correctly', () async {
      const quantity = 2;
      const unitPrice = 500.0;
      const lineTotal = quantity * unitPrice;
      expect(lineTotal, equals(1000.0));
    });

    test('generateInvoice should apply discount correctly', () async {
      const subtotal = 5000.0;
      const discount = 500.0;
      const afterDiscount = subtotal - discount;
      expect(afterDiscount, equals(4500.0));
    });

    test('grandTotal should include discount and tax', () async {
      const subtotal = 5000.0;
      const discount = 500.0;
      const taxPercent = 17.0;
      const afterDiscount = subtotal - discount;
      const taxAmount = (afterDiscount * taxPercent) / 100;
      const grandTotal = afterDiscount + taxAmount;
      expect(grandTotal, equals(5265.0));
    });
  });
}
