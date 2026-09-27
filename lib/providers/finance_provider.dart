import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/daily_sale.dart';
import '../services/db_service.dart';

class FinanceProvider extends ChangeNotifier {
  final List<Expense> _expenses = [];
  final _uuid = const Uuid();

  List<Expense> get expenses => List.unmodifiable(_expenses);

  Future<void> load() async {
    final db = await DBService.instance.database;
    final rows = await db.query('expenses', orderBy: 'date DESC');
    _expenses
      ..clear()
      ..addAll(rows.map((r) => Expense.fromMap(r)));
    notifyListeners();
  }

  Future<void> addExpense(String label, double amount, {DateTime? date}) async {
    final db = await DBService.instance.database;
    final expense = Expense(id: _uuid.v4(), date: date ?? DateTime.now(), label: label, amount: amount);
    await db.insert('expenses', expense.toMap());
    _expenses.insert(0, expense);
    notifyListeners();
  }

  Future<void> deleteExpense(String id) async {
    final db = await DBService.instance.database;
    await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
    _expenses.removeWhere((e) => e.id == id);
    notifyListeners();
  }

  List<Expense> expensesForMonth(int year, int month) =>
      _expenses.where((e) => e.date.year == year && e.date.month == month).toList();

  double totalExpensesForMonth(int year, int month) =>
      expensesForMonth(year, month).fold(0.0, (sum, e) => sum + e.amount);

  /// Net Profit = Total Sales Revenue − COGS − Total Monthly Expenses.
  /// `monthlySales` should be the list of DailySale rows for that month
  /// (pass in from SalesProvider.sales filtered by month).
  double calculateNetProfit(List<DailySale> monthlySales, int year, int month) {
    final revenue = monthlySales.fold(0.0, (sum, s) => sum + s.salePrice);
    final cogs = monthlySales.fold(0.0, (sum, s) => sum + s.costPrice);
    final expenses = totalExpensesForMonth(year, month);
    return revenue - cogs - expenses;
  }
}
