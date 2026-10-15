import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/business_branch.dart';
import '../services/db_service.dart';

/// Local branch registry. Checkout, stock allocation and transfers use this registry;
/// authorization and cloud-side role enforcement must still be handled separately.
class BranchProvider extends ChangeNotifier {
  final _uuid = const Uuid();
  List<BusinessBranch> branches = [];
  bool isLoading = false;

  Future<void> load() async {
    isLoading = true;
    notifyListeners();
    try {
      final db = await DBService.instance.database;
      final rows = await db.query('branches', orderBy: 'isMain DESC, name COLLATE NOCASE');
      branches = rows.map(BusinessBranch.fromMap).toList(growable: false);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<BusinessBranch> saveBranch({
    String? id,
    required String name,
    required String code,
    String address = '',
    String phone = '',
    String managerName = '',
    bool isActive = true,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('Branch name is required.');
    final cleanCode = normalizeBranchCode(code);

    final db = await DBService.instance.database;
    final duplicateCode = await db.query(
      'branches',
      columns: ['id'],
      where: 'UPPER(TRIM(code)) = ? AND id != ?',
      whereArgs: [cleanCode, id ?? ''],
      limit: 1,
    );
    if (duplicateCode.isNotEmpty) {
      throw ArgumentError('Branch code "$cleanCode" is already in use. Choose a unique code.');
    }
    final existing = id == null
        ? <Map<String, Object?>>[]
        : await db.query('branches', where: 'id = ?', whereArgs: [id], limit: 1);
    if (existing.isNotEmpty &&
        (existing.first['isMain'] as num?)?.toInt() == 1 &&
        !isActive) {
      throw StateError('Set another active branch as main before deactivating this branch.');
    }
    final branchCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM branches'),
        ) ??
        0;
    final branch = BusinessBranch(
      id: id ?? _uuid.v4(),
      name: cleanName,
      code: cleanCode,
      address: address.trim(),
      phone: phone.trim(),
      managerName: managerName.trim(),
      isMain: existing.isNotEmpty
          ? (existing.first['isMain'] as num?)?.toInt() == 1
          : branchCount == 0,
      isActive: isActive,
      createdAt: existing.isNotEmpty
          ? DateTime.tryParse(existing.first['createdAt'] as String? ?? '') ?? DateTime.now()
          : DateTime.now(),
    );
    await db.insert(
      'branches',
      branch.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await load();
    return branch;
  }

  Future<void> setMainBranch(String id) async {
    final db = await DBService.instance.database;
    await db.transaction((txn) async {
      final rows = await txn.query('branches', columns: ['id', 'isActive'], where: 'id = ?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) throw StateError('Branch was not found.');
      if ((rows.first['isActive'] as num?)?.toInt() != 1) {
        throw StateError('An inactive branch cannot be set as the main branch.');
      }
      await txn.update('branches', {'isMain': 0});
      await txn.update('branches', {'isMain': 1}, where: 'id = ?', whereArgs: [id]);
    });
    await load();
  }

  Future<void> deleteBranch(String id) async {
    final db = await DBService.instance.database;
    final rows = await db.query('branches', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return;
    if ((rows.first['isMain'] as num?)?.toInt() == 1) {
      throw StateError('Set another branch as main before deleting this branch.');
    }
    final references = <String, String>{
      'branch_stock': 'branchId = ?',
      'branch_cash_transactions': 'branchId = ?',
      'bills': 'branchId = ?',
      'daily_sales': 'branchId = ?',
      'expenses': 'branchId = ?',
      'supplier_orders': 'branchId = ?',
    };
    for (final entry in references.entries) {
      final countRows = await db.rawQuery(
        'SELECT COUNT(*) AS count FROM ${entry.key} WHERE ${entry.value}',
        [id],
      );
      if (((countRows.first['count'] as num?)?.toInt() ?? 0) > 0) {
        throw StateError('This branch has historical records; deactivate it instead of deleting it.');
      }
    }
    final transferRows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM stock_transfers WHERE fromBranchId = ? OR toBranchId = ?',
      [id, id],
    );
    if (((transferRows.first['count'] as num?)?.toInt() ?? 0) > 0) {
      throw StateError('This branch has stock-transfer history; deactivate it instead of deleting it.');
    }
    await db.delete('branches', where: 'id = ?', whereArgs: [id]);
    await load();
  }
}