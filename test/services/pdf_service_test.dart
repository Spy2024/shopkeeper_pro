import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shopkeeper_pro/models/bill.dart';
import 'package:shopkeeper_pro/models/daily_sale.dart';
import 'package:shopkeeper_pro/models/shop.dart';
import 'package:shopkeeper_pro/services/pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory documentsDir;

  setUp(() async {
    documentsDir = await Directory.systemTemp.createTemp('shopkeeper_pdf_test_');
    PdfService.documentsDirectoryProviderForTesting = () async => documentsDir;
  });

  tearDown(() async {
    PdfService.documentsDirectoryProviderForTesting = null;
    if (await documentsDir.exists()) {
      await documentsDir.delete(recursive: true);
    }
  });

  Bill sampleBill({
    String id = 'bill-123',
    double discount = 20,
    double taxPercent = 17,
  }) {
    return Bill(
      id: id,
      date: DateTime(2026, 10, 20, 15, 30),
      customerName: 'Ahmed Khan',
      customerAddress: 'Karachi',
      customerPhone: '+923001234567',
      items: [
        BillItem(productId: 'tea-1', productName: 'Tea', quantity: 2, unitPrice: 150),
        BillItem(productId: 'sugar-1', productName: 'Sugar', quantity: 1, unitPrice: 120),
      ],
      discount: discount,
      taxPercent: taxPercent,
    );
  }

  Shop sampleShop({String? logoPath}) => Shop(
        id: 'shop-1',
        name: 'Test Shop',
        address: 'Market Road, Karachi',
        phone: '03001234567',
        email: 'shop@example.invalid',
        taxNumber: 'NTN-12345',
        logoPath: logoPath,
      );

  test('generateInvoice writes a real, readable PDF file', () async {
    final file = await PdfService.generateInvoice(sampleBill(), sampleShop());

    expect(await file.exists(), isTrue);
    final bytes = await file.readAsBytes();
    expect(bytes.length, greaterThan(500));
    expect(utf8.decode(bytes.take(5).toList()), '%PDF-');
    expect(file.path, contains('invoice_bill-123.pdf'));
  });

  test('missing shop logo does not stop invoice generation', () async {
    final missingLogoPath = '${documentsDir.path}/logo-does-not-exist.png';
    final file = await PdfService.generateInvoice(
      sampleBill(id: 'bill-no-logo'),
      sampleShop(logoPath: missingLogoPath),
    );

    expect(await file.exists(), isTrue);
    expect(utf8.decode((await file.readAsBytes()).take(5).toList()), '%PDF-');
  });

  test('Bill model computes the actual invoice totals', () {
    final bill = sampleBill();

    expect(bill.subtotal, 420);
    expect(bill.taxableSubtotal, 400);
    expect(bill.taxAmount, closeTo(68, 0.0001));
    expect(bill.grandTotal, closeTo(468, 0.0001));
  });

  test('financial statement rejects an inverted date range', () async {
    await expectLater(
      PdfService.generateFinancialStatement(
        startDate: DateTime(2026, 10, 2),
        endDate: DateTime(2026, 10, 1),
        sales: const <DailySale>[],
        expenses: const <Expense>[],
      ),
      throwsArgumentError,
    );
  });
}
