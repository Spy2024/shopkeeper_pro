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

class BackupRestoreService {
  BackupRestoreService._();
  static final BackupRestoreService instance = BackupRestoreService._();
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  static const _tables = <String>[
    'shop',
    'products',
    'bills',
    'bill_items',
    'bill_returns',
    'suppliers',
    'supplier_orders',
    'supplier_order_items',
    'supplier_transactions',
    'daily_sales',
    'expenses',
  ];

  Future<void> _requireOwner(String userId) async {
    if (userId.trim().isEmpty || DBService.instance.activeUserId != userId) {
      throw StateError('The active local database does not belong to this account.');
    }
  }

  Future<File> createBackup(String userId) async {
    await _requireOwner(userId);
    final db = await DBService.instance.database;
    final tables = <String, List<Map<String, dynamic>>>{};
    for (final table in _tables) {
      tables[table] = await db.query(table);
    }
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
    final file = await createBackup(userId);
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
  /// sync can retry.
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
    await uploadBackupToCloud(userId);
  }

  Future<void> restoreLatestCloudBackup(String userId) async {
    await _requireOwner(userId);
    if (FirebaseAuth.instance.currentUser?.uid != userId) {
      throw StateError('Sign in with this account before restoring a cloud backup.');
    }
    final ref = FirebaseStorage.instance.ref().child('users/$userId/backups/latest.json');
    final bytes = await ref.getData(100 * 1024 * 1024);
    if (bytes == null) throw StateError('No cloud backup was found for this account.');
    final documents = await getApplicationDocumentsDirectory();
    final tempFile = File(p.join(documents.path, 'cloud_backup_restore.json'));
    await tempFile.writeAsBytes(bytes, flush: true);
    try {
      await restoreBackup(userId, tempFile);
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
      final rows = sourceTables[table] ?? (table == 'bill_returns' ? <dynamic>[] : null);
      if (rows is! List) throw FormatException('Backup is missing table: $table');
      rowsByTable[table] = rows.map((row) {
        if (row is! Map) throw FormatException('Invalid row in table: $table');
        return Map<String, Object?>.from(row);
      }).toList(growable: false);
    }

    final db = await DBService.instance.database;
    await db.transaction((txn) async {
      for (final table in [
        'bill_returns',
        'bill_items',
        'supplier_order_items',
        'supplier_transactions',
        'bills',
        'supplier_orders',
        'daily_sales',
        'expenses',
        'products',
        'suppliers',
        'shop',
        'sync_queue',
      ]) {
        await txn.delete(table);
      }
      for (final table in _tables) {
        for (final row in rowsByTable[table]!) {
          await txn.insert(table, row, conflictAlgorithm: ConflictAlgorithm.abort);
        }
      }
    });
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
    var salesTotal = 0.0;
    for (final row in billRows) {
      final subtotal = (row['subtotal'] as num).toDouble();
      final discount = (row['discount'] as num?)?.toDouble() ?? 0;
      final taxPercent = (row['taxPercent'] as num?)?.toDouble() ?? 0;
      final taxable = (subtotal - discount).clamp(0.0, double.infinity).toDouble();
      salesTotal += taxable + taxable * taxPercent / 100;
    }
    final expensesTotal = expenseRows.fold<double>(
      0,
      (sum, row) => sum + (row['amount'] as num).toDouble(),
    );
    final refundsTotal = returnRows.fold<double>(
      0,
      (sum, row) => sum + (row['refundAmount'] as num).toDouble(),
    );
    final stockValue = productRows.fold<double>(
      0,
      (sum, row) => sum +
          (row['stockQuantity'] as num).toDouble() *
              (row['costPrice'] as num).toDouble(),
    );

    final document = pw.Document();
    document.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (context) => [
        pw.Text(
          (shop['name'] as String?)?.trim().isNotEmpty == true
              ? shop['name'] as String
              : 'Shopkeeper Pro Statement',
          style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
        ),
        if ((shop['address'] as String?)?.isNotEmpty == true)
          pw.Text(shop['address'] as String),
        if ((shop['phone'] as String?)?.isNotEmpty == true)
          pw.Text('Phone: ${shop['phone']}'),
        const pw.SizedBox(height: 8),
        pw.Text('Generated: ${DateTime.now().toLocal().toString().substring(0, 16)}'),
        pw.Divider(),
        pw.Text('Financial Summary', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.TableHelper.fromTextArray(
          headers: ['Metric', 'Amount / Count'],
          data: [
            ['Total billed sales (before returns)', 'Rs. ${salesTotal.toStringAsFixed(2)}'],
            ['Recorded refunds', 'Rs. ${refundsTotal.toStringAsFixed(2)}'],
            ['Net sales after returns', 'Rs. ${(salesTotal - refundsTotal).toStringAsFixed(2)}'],
            ['Recorded expenses', 'Rs. ${expensesTotal.toStringAsFixed(2)}'],
            ['Current inventory cost value', 'Rs. ${stockValue.toStringAsFixed(2)}'],
            ['Bills recorded', '${billRows.length}'],
            ['Products in inventory', '${productRows.length}'],
          ],
        ),
        const pw.SizedBox(height: 16),
        pw.Text('Recent Bills', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
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
        const pw.SizedBox(height: 12),
        pw.Text('This statement is generated from records currently stored on this device. Verify figures before using it for tax or legal purposes.'),
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
