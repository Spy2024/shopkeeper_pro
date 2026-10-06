import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/daily_sale.dart';
import '../services/db_service.dart';
import '../services/sync_queue_service.dart';

class FinanceProvider extends ChangeNotifier {
  final List<Expense> _expenses = [];
  final _uuid = const Uuid();

  List<Expense> get expenses => List.unmodifiable(_expenses);

  Future<void> load() async {
    final db = await DBService.instance.database;
    final rows = await db.query('expenses', orderBy: 'date DESC');
    _expenses
      ..clear()
      ..addAll(rows.map((r) => Expense.fromMap(Map<String, dynamic>.from(r))));
    notifyListeners();
  }

  Future<void> addExpense(String label, double amount, {DateTime? date}) async {
    if (label.trim().isEmpty || amount <= 0) {
      throw ArgumentError('Invalid expense');
    }
    final expense = Expense(
      id: _uuid.v4(),
      date: date ?? DateTime.now(),
      label: label.trim(),
      amount: amount,
    );
    final db = await DBService.instance.database;
    await db.insert('expenses', expense.toMap());
    _expenses.insert(0, expense);
    try {
      await SyncQueueService.instance.queueOperation(
        operation: 'create',
        tableName: 'expenses',
        documentId: expense.id,
        data: expense.toMap(),
      );
    } catch (e) {
      debugPrint('[Finance] Queue deferred: $e');
    }
    notifyListeners();
  }

  Future<void> deleteExpense(String id) async {
    final db = await DBService.instance.database;
    await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
    _expenses.removeWhere((e) => e.id == id);
    try {
      await SyncQueueService.instance.queueOperation(
        operation: 'delete',
        tableName: 'expenses',
        documentId: id,
        data: const {},
      );
    } catch (e) {
      debugPrint('[Finance] Queue deferred: $e');
    }
    notifyListeners();
  }

  List<Expense> expensesForMonth(int year, int month) =>
      _expenses.where((e) => e.date.year == year && e.date.month == month).toList();

  double totalExpensesForMonth(int year, int month) =>
      expensesForMonth(year, month).fold(0.0, (sum, e) => sum + e.amount);

  double calculateNetProfit(List<DailySale> monthlySales, int year, int month) {
    final revenue = monthlySales.fold(0.0, (sum, s) => sum + s.salePrice);
    final cogs = monthlySales.fold(0.0, (sum, s) => sum + s.costPrice);
    return revenue - cogs - totalExpensesForMonth(year, month);
  }
}
