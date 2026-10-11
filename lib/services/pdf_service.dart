import 'dart:io';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import '../models/bill.dart';
import '../models/shop.dart';
import '../models/supplier.dart';
import '../models/daily_sale.dart';

class PdfService {
  static final _currency = NumberFormat.currency(symbol: 'Rs. ', decimalDigits: 2);
  static final _dateFmt = DateFormat('dd MMM yyyy, hh:mm a');

  static Future<File> generateInvoice(Bill bill, Shop? shop) async {
    final doc = pw.Document();

    // Load shop logo if available
    pw.ImageProvider? logoImage;
    if (shop?.logoPath != null && shop!.logoPath!.isNotEmpty) {
      try {
        final logoFile = File(shop.logoPath!);
        if (await logoFile.exists()) {
          logoImage = pw.MemoryImage(await logoFile.readAsBytes());
        }
      } catch (e) {
        // Logo load failed, continue without it
      }
    }

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80, // receipt-width; swap to a4 for a full page
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // LOGO AND HEADER
            pw.Center(
              child: pw.Column(
                children: [
                  if (logoImage != null)
                    pw.Image(logoImage, width: 60, height: 60)
                  else
                    pw.SizedBox(height: 0),
                  pw.Text(shop?.name ?? 'My Shop',
                      style: const pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
            if (shop?.address != null) pw.Center(child: pw.Text(shop!.address, style: const pw.TextStyle(fontSize: 10))),
            if (shop?.phone != null) pw.Center(child: pw.Text(shop!.phone, style: const pw.TextStyle(fontSize: 10))),
            if (shop?.taxNumber != null && shop!.taxNumber!.isNotEmpty)
              pw.Center(child: pw.Text('NTN: ${shop.taxNumber}', style: const pw.TextStyle(fontSize: 10))),
            pw.Divider(),
            pw.Text('Invoice #: ${_shortId(bill.id)}', style: const pw.TextStyle(fontSize: 11)),
            pw.Text('Date: ${_dateFmt.format(bill.date)}', style: const pw.TextStyle(fontSize: 11)),
            if (bill.customerName != null && bill.customerName!.isNotEmpty)
              pw.Text('Customer: ${bill.customerName}', style: const pw.TextStyle(fontSize: 11)),
            pw.Divider(),
            // LINE ITEMS TABLE
            pw.Table(
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(1),
                2: const pw.FlexColumnWidth(2),
              },
              children: [
                pw.TableRow(children: [
                  pw.Text('Item', style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text('Qty', style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text('Total', style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
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
            pw.Center(child: pw.Text('Thank you for shopping with us!', style: const pw.TextStyle(fontSize: 10))),
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
            pw.Text('Purchase Order', style: const pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
            pw.Text('Order #: ${_shortId(orderId)}'),
            pw.Text('Supplier: ${supplier.name} (${supplier.phone})'),
            pw.Text('Date: ${_dateFmt.format(DateTime.now())}'),
            pw.Divider(),
            pw.TableHelper.fromTextArray(
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
                  style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
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


  /// Creates an A4 sales-and-expenses statement for the selected inclusive date range.
  /// This report is based on recorded daily sales and expenses; it does not yet
  /// reconcile customer credit balances, supplier payables, or recorded returns.
  static Future<File> generateFinancialStatement({
    required DateTime startDate,
    required DateTime endDate,
    required List<DailySale> sales,
    required List<Expense> expenses,
    Shop? shop,
  }) async {
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final endExclusive = DateTime(endDate.year, endDate.month, endDate.day).add(const Duration(days: 1));
    if (!start.isBefore(endExclusive)) {
      throw ArgumentError('Start date must be on or before end date.');
    }

    final reportSales = sales.where((sale) {
      return !sale.date.isBefore(start) && sale.date.isBefore(endExclusive);
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final reportExpenses = expenses.where((expense) {
      return !expense.date.isBefore(start) && expense.date.isBefore(endExclusive);
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final revenue = reportSales.fold<double>(0, (sum, sale) => sum + sale.revenue);
    final cogs = reportSales.fold<double>(0, (sum, sale) => sum + sale.costOfGoods);
    final expenseTotal = reportExpenses.fold<double>(0, (sum, expense) => sum + expense.amount);
    final grossProfit = revenue - cogs;
    final netProfit = grossProfit - expenseTotal;
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Text(shop?.name.trim().isNotEmpty == true ? shop!.name : 'Shopkeeper Pro',
              style: const pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          if (shop?.address.trim().isNotEmpty == true) pw.Text(shop!.address),
          if (shop?.phone.trim().isNotEmpty == true) pw.Text('Phone: ${shop!.phone}'),
          pw.SizedBox(height: 12),
          pw.Text('Financial Statement',
              style: const pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.Text('Period: ${DateFormat('dd MMM yyyy').format(start)} - ${DateFormat('dd MMM yyyy').format(endExclusive.subtract(const Duration(days: 1)))}'),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: const ['Summary', 'Amount'],
            data: [
              ['Sales revenue', _currency.format(revenue)],
              ['Cost of goods sold (COGS)', _currency.format(cogs)],
              ['Gross profit / (loss)', _currency.format(grossProfit)],
              ['Operating expenses', _currency.format(expenseTotal)],
              ['Net profit / (loss)', _currency.format(netProfit)],
            ],
            headerStyle: const pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: {1: pw.Alignment.centerRight},
          ),
          pw.SizedBox(height: 20),
          pw.Text('Sales Detail',
              style: const pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          if (reportSales.isEmpty)
            pw.Text('No sales recorded for this period.')
          else
            pw.TableHelper.fromTextArray(
              headers: const ['Date', 'Item', 'Qty', 'Revenue', 'COGS'],
              data: reportSales.map((sale) => [
                DateFormat('dd MMM yy').format(sale.date),
                sale.productName,
                sale.quantity.toString(),
                _currency.format(sale.revenue),
                _currency.format(sale.costOfGoods),
              ]).toList(),
              headerStyle: const pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellAlignment: pw.Alignment.centerLeft,
              cellAlignments: {
                2: pw.Alignment.centerRight,
                3: pw.Alignment.centerRight,
                4: pw.Alignment.centerRight,
              },
            ),
          pw.SizedBox(height: 20),
          pw.Text('Expense Detail',
              style: const pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          if (reportExpenses.isEmpty)
            pw.Text('No expenses recorded for this period.')
          else
            pw.TableHelper.fromTextArray(
              headers: const ['Date', 'Expense', 'Amount'],
              data: reportExpenses.map((expense) => [
                DateFormat('dd MMM yy').format(expense.date),
                expense.label,
                _currency.format(expense.amount),
              ]).toList(),
              headerStyle: const pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellAlignment: pw.Alignment.centerLeft,
              cellAlignments: {2: pw.Alignment.centerRight},
            ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Note: This statement is calculated from saved daily sales and expense records. '
            'Returns/refunds, customer credit balances, supplier balances, taxes, and opening/closing cash '
            'are not reconciled in this report.',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Generated: ${_dateFmt.format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        ],
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/financial_statement_${DateFormat('yyyyMMdd').format(start)}_${DateFormat('yyyyMMdd').format(endExclusive.subtract(const Duration(days: 1)))}.pdf');
    await file.writeAsBytes(await doc.save());
    return file;
  }

  static String _shortId(String id) => id.length <= 8 ? id.toUpperCase() : id.substring(0, 8).toUpperCase();

  static pw.Widget _row(String label, String value, {bool bold = false}) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: bold ? const pw.TextStyle(fontWeight: pw.FontWeight.bold) : null),
          pw.Text(value, style: bold ? const pw.TextStyle(fontWeight: pw.FontWeight.bold) : null),
        ],
      );
}
