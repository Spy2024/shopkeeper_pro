import 'dart:io';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import '../models/bill.dart';
import '../models/shop.dart';
import '../models/supplier.dart';

class PdfService {
  static final _currency = NumberFormat.currency(symbol: 'Rs. ', decimalDigits: 2);
  static final _dateFmt = DateFormat('dd MMM yyyy, hh:mm a');

  static Future<File> generateInvoice(Bill bill, Shop? shop) async {
    final doc = pw.Document();

    pw.ImageProvider? logoImage;
    if (shop?.logoPath != null && shop!.logoPath!.isNotEmpty) {
      try {
        final logoFile = File(shop.logoPath!);
        if (await logoFile.exists()) {
          logoImage = pw.MemoryImage(await logoFile.readAsBytes());
        }
      } catch (_) {}
    }

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (logoImage != null)
              pw.Center(
                child: pw.Container(
                  height: 50,
                  child: pw.Image(logoImage),
                ),
              ),
            if (shop?.name != null)
              pw.Center(
                child: pw.Text(
                  shop!.name,
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            if (shop?.address != null)
              pw.Center(
                child: pw.Text(
                  shop!.address,
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ),
            if (shop?.phone != null)
              pw.Center(
                child: pw.Text(
                  shop!.phone,
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ),
            if (shop?.taxNumber != null && shop!.taxNumber.isNotEmpty)
              pw.Center(
                child: pw.Text(
                  'NTN: ${shop.taxNumber}',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ),
            pw.SizedBox(height: 5),
            pw.Divider(),
            pw.Text(
              'Invoice #: ${bill.id.length >= 8 ? bill.id.substring(0, 8).toUpperCase() : bill.id.toUpperCase()}',
              style: const pw.TextStyle(fontSize: 11),
            ),
            pw.Text(
              'Date: ${_dateFmt.format(bill.date)}',
              style: const pw.TextStyle(fontSize: 11),
            ),
            pw.Text(
              'Customer: ${bill.customerName}',
              style: const pw.TextStyle(fontSize: 11),
            ),
            pw.Divider(),
            pw.SizedBox(height: 5),
            pw.TableHelper.fromTextArray(
              context: context,
              headers: ['Item', 'Qty', 'Price', 'Total'],
              data: bill.items.map((item) {
                return [
                  item.name,
                  item.quantity.toString(),
                  _currency.format(item.price),
                  _currency.format(item.quantity * item.price),
                ];
              }).toList(),
            ),
            pw.Divider(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Subtotal:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.Text(_currency.format(bill.subtotal)),
              ],
            ),
            if (bill.discount > 0)
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Discount:'),
                  pw.Text('-${_currency.format(bill.discount)}'),
                ],
              ),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Total:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.Text(_currency.format(bill.total), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ],
            ),
            pw.SizedBox(height: 15),
            pw.Center(
              child: pw.Text(
                'Thank you for shopping with us!',
                style: const pw.TextStyle(fontSize: 10),
              ),
            ),
          ],
        ),
      ),
    );

    final output = await getTemporaryDirectory();
    final file = File('${output.path}/invoice_${bill.id}.pdf');
    await file.writeAsBytes(await doc.save());
    return file;
  }

  // Supplier Purchase Order PDF Generator Function
  static Future<File> generatePurchaseOrder({
    required Supplier supplier,
    required List<Map<String, dynamic>> items,
    required double totalAmount,
    Shop? shop,
  }) async {
    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (shop?.name != null)
              pw.Text(
                shop!.name,
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
              ),
            pw.SizedBox(height: 10),
            pw.Text(
              'PURCHASE ORDER',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.Divider(),
            pw.Text('Supplier Name: ${supplier.name}'),
            if (supplier.phone.isNotEmpty) pw.Text('Phone: ${supplier.phone}'),
            pw.Text('Date: ${_dateFmt.format(DateTime.now())}'),
            pw.SizedBox(height: 15),
            pw.TableHelper.fromTextArray(
              context: context,
              headers: ['Item Description', 'Quantity', 'Expected Unit Price', 'Total'],
              data: items.map((item) {
                final qty = (item['quantity'] ?? 1) as num;
                final price = (item['price'] ?? 0.0) as num;
                return [
                  item['name'] ?? '',
                  qty.toString(),
                  _currency.format(price),
                  _currency.format(qty * price),
                ];
              }).toList(),
            ),
            pw.SizedBox(height: 10),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Text(
                  'Total PO Amount: ${_currency.format(totalAmount)}',
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final output = await getTemporaryDirectory();
    final file = File('${output.path}/po_${supplier.id}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(await doc.save());
    return file;
  }
}
