import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sqflite/sqflite.dart';

import 'db_service.dart';
import 'sync_queue_service.dart';
import 'sync_service.dart';

/// Reconciled totals for the financial statement. POS returns are stored as
/// negative daily-sales rows, so returned stock cost offsets the original COGS.
class FinancialStatementTotals {
  final double billedSales;
  final double refunds;
  /// Sales tax collected on bills, less the tax portion of recorded refunds.
  final double taxCollected;
  final double costOfGoods;
  final double expenses;
  final double currentStockValue;
  final int billCount;
  final int productCount;

  const FinancialStatementTotals({
    required this.billedSales,
    required this.refunds,
    required this.taxCollected,
    required this.costOfGoods,
    required this.expenses,
    required this.currentStockValue,
    required this.billCount,
    required this.productCount,
  });

  double get netSales => billedSales - refunds;
  // Sales tax is collected on behalf of the tax authority, not shop revenue.
  double get grossProfit => netSales - taxCollected - costOfGoods;
  double get netProfit => grossProfit - expenses;

  static FinancialStatementTotals fromRecords({
    required List<Map<String, Object?>> billRows,
    required List<Map<String, Object?>> expenseRows,
    required List<Map<String, Object?>> returnRows,
    required List<Map<String, Object?>> productRows,
    required List<Map<String, Object?>> dailySalesRows,
  }) {
    double number(Object? value) => (value as num?)?.toDouble() ?? 0.0;
    final billedSales = billRows.fold<double>(0, (sum, row) {
      final subtotal = number(row['subtotal']);
      final discount = number(row['discount']);
      final taxPercent = number(row['taxPercent']);
      final taxable = (subtotal - discount).clamp(0.0, double.infinity).toDouble();
      return sum + taxable + taxable * taxPercent / 100;
    });
    final refunds = returnRows.fold<double>(
      0, (sum, row) => sum + number(row['refundAmount']));
    final taxRatesByBillId = <String, double>{
      for (final row in billRows)
        if (row['id'] != null)
          row['id'].toString(): number(row['taxPercent']),
    };
    final taxOnBills = billRows.fold<double>(0, (sum, row) {
      final subtotal = number(row['subtotal']);
      final discount = number(row['discount']);
      final taxable = (subtotal - discount).clamp(0.0, double.infinity).toDouble();
      return sum + taxable * number(row['taxPercent']) / 100;
    });
    // Refund amounts are stored tax-inclusive. Reverse the tax portion using
    // the original bill's rate, so refunded tax is not reported as payable.
    final refundedTax = returnRows.fold<double>(0, (sum, row) {
      final rate = taxRatesByBillId[row['billId']?.toString()] ?? 0.0;
      final refund = number(row['refundAmount']);
      final denominator = 100 + rate;
      return sum + (denominator <= 0 ? 0.0 : refund * rate / denominator);
    });
    final taxCollected = taxOnBills - refundedTax;
    // Bill totals above represent POS bills only. Include COGS for POS sales
    // and their returns, but exclude manually entered sales to avoid reducing
    // profit for revenue that is not part of billedSales.
    final costOfGoods = dailySalesRows
        .where((row) => row['source'] == 'pos' || row['source'] == 'return')
        .fold<double>(
          0,
          (sum, row) => sum + number(row['costPrice']) * number(row['quantity']),
        );
    final expenses = expenseRows.fold<double>(
      0, (sum, row) => sum + number(row['amount']));
    final stockValue = productRows.fold<double>(
      0, (sum, row) => sum + number(row['stockQuantity']) * number(row['costPrice']));
    return FinancialStatementTotals(
      billedSales: billedSales,
      refunds: refunds,
      taxCollected: taxCollected,
      costOfGoods: costOfGoods,
      expenses: expenses,
      currentStockValue: stockValue,
      billCount: billRows.length,
      productCount: productRows.length,
    );
  }
}

class BackupRestoreService {
  BackupRestoreService._();
  static final BackupRestoreService instance = BackupRestoreService._();
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  static const _tables = <String>[
    'shop',
    'branches',
    'products',
    'branch_stock',
    'stock_transfers',
    'branch_cash_transactions',
    'customers',
    'customer_ledger',
    'bills',
    'bill_items',
    'bill_returns',
    'payment_allocations',
    'suppliers',
    'supplier_orders',
    'supplier_order_items',
    'supplier_transactions',
    'daily_sales',
    'expenses',
  ];

  void _ensureOwnerStillActive(String userId) {
    if (userId.trim().isEmpty || DBService.instance.activeUserId != userId) {
      throw StateError('The active local database does not belong to this account.');
    }
  }

  Future<void> _requireOwner(String userId) async {
    _ensureOwnerStillActive(userId);
  }

  Future<File> createBackup(String userId) async {
    await _requireOwner(userId);
    final db = await DBService.instance.database;
    await _requireOwner(userId);
    final tables = <String, List<Map<String, dynamic>>>{};
    // Read every table from one SQLite transaction so a concurrent checkout
    // cannot produce a backup with bills from one moment and stock from another.
    // Recheck ownership inside the transaction: a sign-out/account switch must
    // not let rows from the previous database be exported under another user ID.
    await db.transaction((txn) async {
      _ensureOwnerStillActive(userId);
      for (final table in _tables) {
        _ensureOwnerStillActive(userId);
        tables[table] = await txn.query(table);
      }
      _ensureOwnerStillActive(userId);
    });
    await _requireOwner(userId);
    final now = DateTime.now().toUtc();
    final payload = <String, dynamic>{
      'format': 'shopkeeper-pro-backup',
      'schemaVersion': 1,
      'userId': userId,
      'createdAt': now.toIso8601String(),
      'tables': tables,
    };
    final documents = await getApplicationDocumentsDirectory();
    final backupDir = Directory(p.join(documents.path, 'backups'));
    await backupDir.create(recursive: true);
    final file = File(p.join(
      backupDir.path,
      'shopkeeper_backup_${now.toIso8601String().replaceAll(':', '-')}.json',
    ));
    await file.writeAsString(jsonEncode(payload), flush: true);
    return file;
  }


  Future<String> uploadBackupToCloud(String userId) async {
    await _requireOwner(userId);
    if (FirebaseAuth.instance.currentUser?.uid != userId) {
      throw StateError('Sign in with this account before uploading a cloud backup.');
    }
    // Manual backups should not race an active sync or cloud restore.
    await SyncService.instance.ensureCloudRestoreReady(userId);
    return _uploadBackupToCloudFile(userId);
  }

  Future<String> _uploadBackupToCloudFile(String userId) async {
    await _requireOwner(userId);
    if (FirebaseAuth.instance.currentUser?.uid != userId) {
      throw StateError('Sign in with this account before uploading a cloud backup.');
    }
    final file = await createBackup(userId);
    // The backup generation is asynchronous; do not upload after an account
    // switch or sign-out while the local snapshot was being written.
    await _requireOwner(userId);
    if (FirebaseAuth.instance.currentUser?.uid != userId) {
      throw StateError('Sign in with this account before uploading a cloud backup.');
    }
    final ref = FirebaseStorage.instance.ref().child('users/$userId/backups/latest.json');
    await ref.putFile(
      file,
      SettableMetadata(contentType: 'application/json'),
    );
    await _secureStorage.write(
      key: 'last_cloud_backup_$userId',
      value: DateTime.now().toUtc().toIso8601String(),
    );
    return ref.fullPath;
  }

  /// Creates at most one automatic cloud backup per 24 hours when a successful
  /// sync occurs. A failed upload does not advance the timestamp, so the next
  /// sync can retry. This uses the internal upload path because SyncService
  /// deliberately holds its sync lock while invoking this method.
  Future<void> maybeCreateAutomaticCloudBackup(String userId) async {
    if (FirebaseAuth.instance.currentUser?.uid != userId) return;
    final last = await _secureStorage.read(key: 'last_cloud_backup_$userId');
    if (last != null) {
      final lastTime = DateTime.tryParse(last);
      if (lastTime != null &&
          DateTime.now().toUtc().difference(lastTime) < const Duration(hours: 24)) {
        return;
      }
    }
    await _uploadBackupToCloudFile(userId);
  }

  Future<bool> restoreLatestCloudBackup(String userId) async {
    await _requireOwner(userId);
    if (FirebaseAuth.instance.currentUser?.uid != userId) {
      throw StateError('Sign in with this account before restoring a cloud backup.');
    }
    final ref = FirebaseStorage.instance.ref().child('users/$userId/backups/latest.json');
    final bytes = await ref.getData(100 * 1024 * 1024);
    if (bytes == null) throw StateError('No cloud backup was found for this account.');
    await _requireOwner(userId);
    if (FirebaseAuth.instance.currentUser?.uid != userId) {
      throw StateError('Sign in with this account before restoring a cloud backup.');
    }
    final documents = await getApplicationDocumentsDirectory();
    final tempFile = File(p.join(documents.path, 'cloud_backup_restore.json'));
    await tempFile.writeAsBytes(bytes, flush: true);
    try {
      await restoreBackup(userId, tempFile);
      // The restored local snapshot is authoritative. If reconciliation fails,
      // keep the durable pending marker so a later sync retries before pulling cloud.
      try {
        await SyncService.instance.replaceCloudWithLocalSnapshot(userId);
        return true;
      } catch (e) {
        debugPrint('[Backup] Local restore succeeded; cloud reconciliation remains pending: $e');
        return false;
      }
    } finally {
      if (await tempFile.exists()) await tempFile.delete();
    }
  }

  Future<void> restoreBackup(String userId, File file, {bool allowDifferentAccount = false}) async {
    await _requireOwner(userId);
    if (!await file.exists()) throw FileSystemException('Backup file does not exist.', file.path);
    if (await file.length() > 100 * 1024 * 1024) {
      throw const FormatException('Backup file is larger than the 100 MB safety limit.');
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != 'shopkeeper-pro-backup' ||
        decoded['schemaVersion'] != 1 ||
        (!allowDifferentAccount && decoded['userId'] != userId) ||
        decoded['tables'] is! Map<String, dynamic>) {
      throw const FormatException(
        'This backup is invalid, unsupported, or belongs to a different account.',
      );
    }
    final sourceTables = decoded['tables'] as Map<String, dynamic>;
    final rowsByTable = <String, List<Map<String, Object?>>>{};
    for (final table in _tables) {
      // Older schemaVersion 1 backups may predate supplier order item
      // preservation. Restore those backups without line items rather than
      // rejecting the entire backup.
      final rows = sourceTables[table] ??
          ((table == 'bill_returns' ||
                  table == 'customers' ||
                  table == 'supplier_order_items' ||
                  table == 'branches' ||
                  table == 'branch_stock' ||
                  table == 'stock_transfers' ||
                  table == 'branch_cash_transactions' ||
                  table == 'customer_ledger' ||
                  table == 'payment_allocations')
              ? <dynamic>[]
              : null);
      if (rows is! List) throw FormatException('Backup is missing table: $table');
      rowsByTable[table] = rows.map((row) {
        if (row is! Map) throw FormatException('Invalid row in table: $table');
        return Map<String, Object?>.from(row);
      }).toList(growable: false);
    }

    final db = await DBService.instance.database;
    await _requireOwner(userId);
    await db.transaction((txn) async {
      _ensureOwnerStillActive(userId);
      for (final table in [
        'payment_allocations',
        'bill_returns',
        'bill_items',
        'supplier_order_items',
        'supplier_transactions',
        'stock_transfers',
        'branch_cash_transactions',
        'customer_ledger',
        'branch_stock',
        'bills',
        'supplier_orders',
        'daily_sales',
        'expenses',
        'products',
        'customers',
        'suppliers',
        'branches',
        'shop',
        'sync_queue',
      ]) {
        _ensureOwnerStillActive(userId);
        await txn.delete(table);
      }
      for (final table in _tables) {
        _ensureOwnerStillActive(userId);
        for (final row in rowsByTable[table]!) {
          _ensureOwnerStillActive(userId);
          await txn.insert(table, row, conflictAlgorithm: ConflictAlgorithm.abort);
        }
      }
      _ensureOwnerStillActive(userId);
      // Persist reconciliation intent in the same SQLite transaction as the
      // restored rows, so an app interruption cannot silently skip cloud cleanup.
      await txn.insert(
        'sync_metadata',
        {'key': 'cloud_restore_pending', 'value': userId},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    await _requireOwner(userId);
    await SyncQueueService.instance.reloadPendingQueue();
    debugPrint('[Backup] Restore completed for account $userId');
  }

  Future<File> createFinancialStatement(String userId) async {
    await _requireOwner(userId);
    final db = await DBService.instance.database;
    final shopRows = await db.query('shop', limit: 1);
    final shop = shopRows.isEmpty ? <String, Object?>{} : shopRows.first;
    final billRows = await db.rawQuery('''
      SELECT b.id, b.date, b.discount, b.taxPercent,
             COALESCE(SUM(bi.quantity * bi.unitPrice), 0) AS subtotal
      FROM bills b
      LEFT JOIN bill_items bi ON bi.billId = b.id
      GROUP BY b.id
      ORDER BY b.date DESC
    ''');
    final expenseRows = await db.query('expenses', orderBy: 'date DESC');
    final returnRows = await db.query('bill_returns');
    final productRows = await db.query('products');
    final dailySalesRows = await db.query(
      'daily_sales',
      where: "source IN ('pos', 'return')",
    );
    final totals = FinancialStatementTotals.fromRecords(
      billRows: billRows,
      expenseRows: expenseRows,
      returnRows: returnRows,
      productRows: productRows,
      dailySalesRows: dailySalesRows,
    );

    final document = pw.Document();
    document.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (context) => [
        pw.Text(
          (shop['name'] as String?)?.trim().isNotEmpty == true
              ? shop['name'] as String
              : 'Shopkeeper Pro Statement',
          style: const pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
        ),
        if ((shop['address'] as String?)?.isNotEmpty == true)
          pw.Text(shop['address'] as String),
        if ((shop['phone'] as String?)?.isNotEmpty == true)
          pw.Text('Phone: ${shop['phone']}'),
        pw.SizedBox(height: 8),
        pw.Text('Generated: ${DateTime.now().toLocal().toString().substring(0, 16)}'),
        pw.Divider(),
        pw.Text('Financial Summary', style: const pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.TableHelper.fromTextArray(
          headers: ['Metric', 'Amount / Count'],
          data: [
            ['Total billed sales (tax included)', 'Rs. ${totals.billedSales.toStringAsFixed(2)}'],
            ['Recorded refunds', 'Rs. ${totals.refunds.toStringAsFixed(2)}'],
            ['Net sales after returns (tax included)', 'Rs. ${totals.netSales.toStringAsFixed(2)}'],
            ['Net sales tax payable (estimated)', 'Rs. ${totals.taxCollected.toStringAsFixed(2)}'],
            ['Cost of goods sold (net of returned cost)', 'Rs. ${totals.costOfGoods.toStringAsFixed(2)}'],
            ['Gross profit after returns', 'Rs. ${totals.grossProfit.toStringAsFixed(2)}'],
            ['Recorded expenses', 'Rs. ${totals.expenses.toStringAsFixed(2)}'],
            ['Net operating profit / loss', 'Rs. ${totals.netProfit.toStringAsFixed(2)}'],
            ['Current inventory cost value', 'Rs. ${totals.currentStockValue.toStringAsFixed(2)}'],
            ['Bills recorded', '${totals.billCount}'],
            ['Products in inventory', '${totals.productCount}'],
          ],
        ),
        pw.SizedBox(height: 16),
        pw.Text('Recent Bills', style: const pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.TableHelper.fromTextArray(
          headers: ['Date', 'Bill ID', 'Total (Rs.)'],
          data: billRows.take(250).map((row) {
            final subtotal = (row['subtotal'] as num).toDouble();
            final discount = (row['discount'] as num?)?.toDouble() ?? 0;
            final taxPercent = (row['taxPercent'] as num?)?.toDouble() ?? 0;
            final taxable = (subtotal - discount).clamp(0.0, double.infinity).toDouble();
            final total = taxable + taxable * taxPercent / 100;
            final id = row['id'].toString();
            return [
              row['date'].toString().split('T').first,
              id.length > 8 ? id.substring(0, 8).toUpperCase() : id.toUpperCase(),
              total.toStringAsFixed(2),
            ];
          }).toList(),
        ),
        pw.SizedBox(height: 12),
        pw.Text('This statement is generated from records currently stored on this device. Sales are tax-inclusive; profit is an operational estimate based on recorded POS cost rows and expenses, not a tax filing or audited financial statement. Verify figures before official use.'),
      ],
    ));
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(documents.path, 'statements'));
    await directory.create(recursive: true);
    final file = File(p.join(
      directory.path,
      'financial_statement_${DateTime.now().millisecondsSinceEpoch}.pdf',
    ));
    await file.writeAsBytes(await document.save(), flush: true);
    return file;
  }
}