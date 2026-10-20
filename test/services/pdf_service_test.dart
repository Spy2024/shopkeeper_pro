import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shopkeeper_pro/models/bill.dart';
import 'package:shopkeeper_pro/models/daily_sale.dart';
import 'package:shopkeeper_pro/models/shop.dart';
import 'package:shopkeeper_pro/services/pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documentsDir;

  setUp(() async {
    documentsDir = await Directory.systemTemp.createTemp('shopkeeper_pdf_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getApplicationDocumentsPath') return documentsDir.path;
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    if (await documentsDir.exists()) {
      await documentsDir.delete(recursive: true);
    }
  });

  Bill _sampleBill({
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

  Shop _sampleShop({String? logoPath}) => Shop(
        id: 'shop-1',
        name: 'Test Shop',
        address: 'Market Road, Karachi',
        phone: '03001234567',
        email: 'shop@example.invalid',
        taxNumber: 'NTN-12345',
        logoPath: logoPath,
      );

  test('generateInvoice writes a real, readable PDF file', () async {
    final file = await PdfService.generateInvoice(_sampleBill(), _sampleShop());

    expect(await file.exists(), isTrue);
    final bytes = await file.readAsBytes();
    expect(bytes.length, greaterThan(500));
    expect(utf8.decode(bytes.take(5).toList()), '%PDF-');
    expect(file.path, contains('invoice_bill-123.pdf'));
  });

  test('missing shop logo does not stop invoice generation', () async {
    final missingLogoPath = '${documentsDir.path}/logo-does-not-exist.png';
    final file = await PdfService.generateInvoice(
      _sampleBill(id: 'bill-no-logo'),
      _sampleShop(logoPath: missingLogoPath),
    );

    expect(await file.exists(), isTrue);
    expect(utf8.decode((await file.readAsBytes()).take(5).toList()), '%PDF-');
  });

  test('Bill model computes the actual invoice totals', () {
    final bill = _sampleBill();

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
