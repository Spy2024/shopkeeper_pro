import 'dart:io';
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

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80, // receipt-width; swap to a4 for a full page
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(
              child: pw.Text(shop?.name ?? 'My Shop',
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            ),
            if (shop?.address != null) pw.Center(child: pw.Text(shop!.address)),
            if (shop?.phone != null) pw.Center(child: pw.Text(shop!.phone)),
            if (shop?.taxNumber != null && shop!.taxNumber!.isNotEmpty)
              pw.Center(child: pw.Text('NTN: ${shop.taxNumber}')),
            pw.Divider(),
            pw.Text('Invoice #: ${bill.id.substring(0, 8).toUpperCase()}'),
            pw.Text('Date: ${_dateFmt.format(bill.date)}'),
            if (bill.customerName != null && bill.customerName!.isNotEmpty)
              pw.Text('Customer: ${bill.customerName}'),
            pw.Divider(),
            pw.Table(
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(1),
                2: const pw.FlexColumnWidth(2),
              },
              children: [
                pw.TableRow(children: [
                  pw.Text('Item', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text('Qty', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text('Total', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                ]),
                ...bill.items.map((item) => pw.TableRow(children: [
                      pw.Text(item.productName),
                      pw.Text('${item.quantity}'),
                      pw.Text(_currency.format(item.lineTotal)),
                    ])),
              ],
            ),
            pw.Divider(),
            _row('Subtotal', _currency.format(bill.subtotal)),
            if (bill.discount > 0) _row('Discount', '-${_currency.format(bill.discount)}'),
            if (bill.taxPercent > 0)
              _row('Tax (${bill.taxPercent.toStringAsFixed(1)}%)', _currency.format(bill.taxAmount)),
            pw.Divider(),
            _row('Grand Total', _currency.format(bill.grandTotal), bold: true),
            pw.SizedBox(height: 12),
            pw.Center(child: pw.Text('Thank you for shopping with us!')),
          ],
        ),
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/invoice_${bill.id}.pdf');
    await file.writeAsBytes(await doc.save());
    return file;
  }

  static Future<File> generatePurchaseOrder(
      String orderId, Supplier supplier, List<Map<String, dynamic>> items, double total) async {
    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Purchase Order', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
            pw.Text('Order #: ${orderId.substring(0, 8).toUpperCase()}'),
            pw.Text('Supplier: ${supplier.name} (${supplier.phone})'),
            pw.Text('Date: ${_dateFmt.format(DateTime.now())}'),
            pw.Divider(),
            pw.Table.fromTextArray(
              headers: ['Product', 'Required Qty', 'Estimated Price', 'Estimated Total'],
              data: items
                  .map((i) => [
                        i['productName'],
                        '${i['requiredQuantity']}',
                        _currency.format(i['estimatedPrice']),
                        _currency.format(i['requiredQuantity'] * i['estimatedPrice']),
                      ])
                  .toList(),
            ),
            pw.Divider(),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text('Estimated Order Total: ${_currency.format(total)}',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/purchase_order_$orderId.pdf');
    await file.writeAsBytes(await doc.save());
    return file;
  }

  static pw.Widget _row(String label, String value, {bool bold = false}) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: bold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null),
          pw.Text(value, style: bold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null),
        ],
      );
}
