import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class SnookerReportService {
  static final _money = NumberFormat.currency(locale: 'en_PK', symbol: 'Rs. ', decimalDigits: 2);

  static Future<List<int>> buildDailyPdf(Map<String, Object?> report) async {
    final document = pw.Document();
    const navy = PdfColor.fromInt(0xFF0B3D91);
    const teal = PdfColor.fromInt(0xFF14B8A6);
    const gold = PdfColor.fromInt(0xFFFFBF24);
    final wins = (report['playerWins'] as List? ?? const []).cast<Map<String, Object?>>();
    document.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (_) => pw.Container(
        padding: const pw.EdgeInsets.all(16),
        decoration: const pw.BoxDecoration(color: navy),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('SHOPKEEPER PRO', style: pw.TextStyle(color: PdfColors.white, fontSize: 10, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('SNOOKER CLUB REPORT', style: pw.TextStyle(color: PdfColors.white, fontSize: 18, fontWeight: pw.FontWeight.bold)),
          ]),
          pw.Container(width: 12, height: 36, color: gold),
        ]),
      ),
      build: (_) => [
        pw.SizedBox(height: 16),
        pw.Text('Period: ${report['from'] ?? ''} — ${report['to'] ?? ''}', style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headers: const ['Metric', 'Amount / Count'],
          headerDecoration: const pw.BoxDecoration(color: teal),
          headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 10),
          data: [
            ['Completed games', '${report['completedGames'] ?? 0}'],
            ['Game fees earned', _money.format(report['gameFeesEarned'] ?? 0)],
            ['Payments received', _money.format(report['paymentsReceived'] ?? 0)],
            ['Refunds', _money.format(report['refunds'] ?? 0)],
            ['Outstanding game fees', _money.format(report['outstandingGameFees'] ?? 0)],
            ['Refreshment sales', _money.format(report['refreshmentSales'] ?? 0)],
            ['Refreshment cost of goods', _money.format(report['refreshmentCost'] ?? 0)],
            ['Club expenses', _money.format(report['snookerExpenses'] ?? 0)],
            ['Operating result before other costs', _money.format(report['operatingResultBeforeOtherCosts'] ?? 0)],
          ],
        ),
        pw.SizedBox(height: 20),
        pw.Text('Player wins', style: pw.TextStyle(fontSize: 14, color: navy, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        if (wins.isEmpty) pw.Text('No completed games in this period.', style: const pw.TextStyle(fontSize: 10))
        else pw.TableHelper.fromTextArray(
          headers: const ['Player', 'Wins'],
          headerDecoration: const pw.BoxDecoration(color: navy),
          headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 10),
          data: wins.map((row) => [row['name']?.toString() ?? '', row['wins']?.toString() ?? '0']).toList(),
        ),
        pw.SizedBox(height: 18),
        pw.Text('Game fees and refreshment sales are reported separately. Unpaid fees are not counted as cash received.', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      ],
    ));
    return document.save();
  }

  static Future<void> shareDailyReport(Map<String, Object?> report) async {
    final bytes = await buildDailyPdf(report);
    await Printing.sharePdf(bytes: bytes, filename: 'snooker-club-report.pdf');
  }

  static Future<void> printDailyReport(Map<String, Object?> report) async {
    final bytes = await buildDailyPdf(report);
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }
}
