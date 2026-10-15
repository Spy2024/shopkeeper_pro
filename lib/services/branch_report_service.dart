import 'db_service.dart';

class BranchReport {
  final String branchId;
  final DateTime start;
  final DateTime end;
  final double revenue;
  final double expenses;
  final double cashReceived;
  final double cashOut;
  final double creditIssued;

  const BranchReport({
    required this.branchId,
    required this.start,
    required this.end,
    required this.revenue,
    required this.expenses,
    required this.cashReceived,
    required this.cashOut,
    required this.creditIssued,
  });

  double get netOperatingResult => revenue - expenses;
}

class BranchReportService {
  BranchReportService._();
  static final BranchReportService instance = BranchReportService._();

  Future<BranchReport> forPeriod({
    required String branchId,
    required DateTime start,
    required DateTime end,
  }) async {
    final cleanBranchId = branchId.trim();
    if (cleanBranchId.isEmpty) throw ArgumentError('Branch is required.');
    if (end.isBefore(start)) throw ArgumentError('Report end date must not be before start date.');

    final db = await DBService.instance.database;
    final startDate = DateTime(start.year, start.month, start.day).toIso8601String();
    final endDate = DateTime(end.year, end.month, end.day, 23, 59, 59, 999).toIso8601String();

    final branch = await db.query(
      'branches',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [cleanBranchId],
      limit: 1,
    );
    if (branch.isEmpty) throw StateError('Branch does not exist.');

    final salesRows = await db.rawQuery(
      'SELECT COALESCE(SUM(salePrice * quantity), 0) AS total '
      'FROM daily_sales WHERE branchId = ? AND date >= ? AND date <= ?',
      [cleanBranchId, startDate, endDate],
    );
    final expenseRows = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) AS total FROM expenses '
      'WHERE branchId = ? AND date >= ? AND date <= ?',
      [cleanBranchId, startDate, endDate],
    );
    final cashRows = await db.rawQuery(
      "SELECT COALESCE(SUM(CASE WHEN type IN ('cash_in','sale') THEN amount ELSE 0 END), 0) AS cashIn, "
      "COALESCE(SUM(CASE WHEN type IN ('cash_out','refund','expense','transfer_out') THEN amount ELSE 0 END), 0) AS cashOut "
      'FROM branch_cash_transactions WHERE branchId = ? AND date >= ? AND date <= ?',
      [cleanBranchId, startDate, endDate],
    );
    final creditRows = await db.rawQuery(
      "SELECT COALESCE(SUM(CASE WHEN type = 'sale_due' THEN amount ELSE 0 END), 0) AS total "
      'FROM customer_ledger WHERE referenceId IN '
      '(SELECT id FROM bills WHERE branchId = ? AND date >= ? AND date <= ?)',
      [cleanBranchId, startDate, endDate],
    );

    double value(List<Map<String, Object?>> rows, String key) =>
        (rows.first[key] as num?)?.toDouble() ?? 0;

    return BranchReport(
      branchId: cleanBranchId,
      start: DateTime(start.year, start.month, start.day),
      end: DateTime(end.year, end.month, end.day),
      revenue: value(salesRows, 'total'),
      expenses: value(expenseRows, 'total'),
      cashReceived: value(cashRows, 'cashIn'),
      cashOut: value(cashRows, 'cashOut'),
      creditIssued: value(creditRows, 'total'),
    );
  }

  Future<List<Map<String, Object?>>> activeBranches() async {
    final db = await DBService.instance.database;
    return db.query(
      'branches',
      columns: ['id', 'name', 'code'],
      where: 'isActive = ?',
      whereArgs: [1],
      orderBy: 'isMain DESC, name COLLATE NOCASE',
    );
  }
}
