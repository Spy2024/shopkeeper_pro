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

  /// Generates a premium, full-page colour invoice for sharing or saving as PDF.
  /// Thermal receipt printing should use a dedicated 58/80mm layout so this
  /// branded A4 document does not reduce printer compatibility.
  static Future<File> generateInvoice(Bill bill, Shop? shop) async {
    final doc = pw.Document();
    const navy = PdfColor.fromInt(0xFF142B4A);
    const teal = PdfColor.fromInt(0xFF0F9D91);
    const gold = PdfColor.fromInt(0xFFF2B84B);
    const pale = PdfColor.fromInt(0xFFF2F6FA);
    const border = PdfColor.fromInt(0xFFE2E8F0);

    pw.ImageProvider? logoImage;
    if (shop?.logoPath != null && shop!.logoPath!.isNotEmpty) {
      try {
        final logoFile = File(shop.logoPath!);
        if (await logoFile.exists()) {
          logoImage = pw.MemoryImage(await logoFile.readAsBytes());
        }
      } catch (_) {
        // A missing/unreadable logo must not prevent invoice generation.
      }
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        footer: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 10),
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: border, width: 0.8)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Powered by Shopkeeper Pro',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
              pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            ],
          ),
        ),
        build: (context) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(22),
            decoration: const pw.BoxDecoration(
              color: navy,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(14)),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logoImage != null)
                  pw.Container(
                    width: 58,
                    height: 58,
                    margin: const pw.EdgeInsets.only(right: 16),
                    padding: const pw.EdgeInsets.all(4),
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.white,
                      borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
                    ),
                    child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                  ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        shop?.name.trim().isNotEmpty == true ? shop!.name : 'Shopkeeper Pro',
                        style: const pw.TextStyle(
                          fontSize: 21,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                      ),
                      if (shop?.address.trim().isNotEmpty == true)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 5),
                          child: pw.Text(shop!.address,
                              style: const pw.TextStyle(fontSize: 9, color: PdfColors.white)),
                        ),
                      if (shop?.phone.trim().isNotEmpty == true)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 3),
                          child: pw.Text('Phone: ${shop!.phone}',
                              style: const pw.TextStyle(fontSize: 9, color: PdfColors.white)),
                        ),
                      if (shop?.email?.trim().isNotEmpty == true)
                        pw.Padding(padding: const pw.EdgeInsets.only(top: 3), child: pw.Text('Email: ${shop!.email}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.white))),
                      if (shop?.website?.trim().isNotEmpty == true)
                        pw.Padding(padding: const pw.EdgeInsets.only(top: 3), child: pw.Text('Web: ${shop!.website}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.white))),
                      if (shop?.facebookUrl?.trim().isNotEmpty == true)
                        pw.Padding(padding: const pw.EdgeInsets.only(top: 3), child: pw.Text('Facebook: ${shop!.facebookUrl}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.white))),
                      if (shop?.instagramUrl?.trim().isNotEmpty == true)
                        pw.Padding(padding: const pw.EdgeInsets.only(top: 3), child: pw.Text('Instagram: ${shop!.instagramUrl}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.white))),
                      if (shop?.socialUrl?.trim().isNotEmpty == true)
                        pw.Padding(padding: const pw.EdgeInsets.only(top: 3), child: pw.Text('Social: ${shop!.socialUrl}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.white))),
                      if (shop?.taxNumber?.trim().isNotEmpty == true)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 3),
                          child: pw.Text('NTN: ${shop!.taxNumber}',
                              style: const pw.TextStyle(fontSize: 9, color: PdfColors.white)),
                        ),
                    ],
                  ),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: const pw.BoxDecoration(
                    color: teal,
                    borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
                  ),
                  child: pw.Text('INVOICE',
                      style: const pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 1.2,
                      )),
                ),
              ],
            ),
          ),
          pw.Container(height: 4, margin: const pw.EdgeInsets.only(bottom: 20), color: gold),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(14),
                  decoration: const pw.BoxDecoration(
                    color: pale,
                    borderRadius: pw.BorderRadius.all(pw.Radius.circular(10)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('BILL TO',
                          style: const pw.TextStyle(
                            color: teal,
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                            letterSpacing: 1,
                          )),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        bill.customerName?.trim().isNotEmpty == true
                            ? bill.customerName!
                            : 'Walk-in Customer',
                        style: const pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: navy),
                      ),
                      if (bill.customerAddress?.trim().isNotEmpty == true) pw.Padding(padding: const pw.EdgeInsets.only(top: 4), child: pw.Text('Address: ${bill.customerAddress}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700))),
                      if (bill.customerPhone?.trim().isNotEmpty == true) pw.Padding(padding: const pw.EdgeInsets.only(top: 3), child: pw.Text('Phone: ${bill.customerPhone}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700))),
                      if (bill.customerEmail?.trim().isNotEmpty == true) pw.Padding(padding: const pw.EdgeInsets.only(top: 3), child: pw.Text('Email: ${bill.customerEmail}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700))),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(14),
                  decoration: const pw.BoxDecoration(
                    color: pale,
                    borderRadius: pw.BorderRadius.all(pw.Radius.circular(10)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('INVOICE DETAILS',
                          style: const pw.TextStyle(
                            color: teal,
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                            letterSpacing: 1,
                          )),
                      pw.SizedBox(height: 6),
                      pw.Text('#${_shortId(bill.id)}',
                          style: const pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: navy)),
                      pw.SizedBox(height: 3),
                      pw.Text(_dateFmt.format(bill.date),
                          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 22),
          pw.Text('Items purchased',
              style: const pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: navy)),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: const ['Product / Description', 'Qty', 'Unit price', 'Line total'],
            data: bill.items.map((item) => [
              item.productName,
              item.quantity.toString(),
              _currency.format(item.unitPrice),
              _currency.format(item.lineTotal),
            ]).toList(),
            headerStyle: const pw.TextStyle(
              color: PdfColors.white,
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
            ),
            headerDecoration: const pw.BoxDecoration(color: navy),
            headerAlignment: pw.Alignment.centerLeft,
            cellStyle: const pw.TextStyle(fontSize: 9, color: navy),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 9),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: const {
              1: pw.Alignment.center,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
            },
            oddRowDecoration: const pw.BoxDecoration(color: pale),
            border: const pw.TableBorder(
              horizontalInside: pw.BorderSide(color: border, width: 0.5),
              bottom: pw.BorderSide(color: border, width: 0.8),
            ),
          ),
          pw.SizedBox(height: 18),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(14),
                  decoration: const pw.BoxDecoration(
                    color: pale,
                    borderRadius: pw.BorderRadius.all(pw.Radius.circular(10)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('THANK YOU!',
                          style: const pw.TextStyle(
                            color: teal,
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                          )),
                      pw.SizedBox(height: 5),
                      pw.Text('We appreciate your business.',
                          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 16),
              pw.SizedBox(
                width: 220,
                child: pw.Column(
                  children: [
                    _row('Subtotal', _currency.format(bill.subtotal)),
                    if (bill.discount > 0) ...[
                      pw.SizedBox(height: 7),
                      _row('Discount', '-${_currency.format(bill.discount)}'),
                    ],
                    if (bill.taxPercent > 0) ...[
                      pw.SizedBox(height: 7),
                      _row('Tax (${bill.taxPercent.toStringAsFixed(1)}%)', _currency.format(bill.taxAmount)),
                    ],
                    pw.SizedBox(height: 12),
                    pw.Container(
                      width: double.infinity,
                      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                      decoration: const pw.BoxDecoration(
                        color: teal,
                        borderRadius: pw.BorderRadius.all(pw.Radius.circular(9)),
                      ),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('GRAND TOTAL',
                              style: const pw.TextStyle(
                                color: PdfColors.white,
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold,
                              )),
                          pw.Text(_currency.format(bill.grandTotal),
                              style: const pw.TextStyle(
                                color: PdfColors.white,
                                fontSize: 12,
                                fontWeight: pw.FontWeight.bold,
                              )),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
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
