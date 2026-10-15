import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/daily_sale.dart';
import '../services/db_service.dart';
import '../services/sync_queue_service.dart';

class SalesProvider extends ChangeNotifier {
  final List<DailySale> _sales = [];
  final _uuid = const Uuid();

  List<DailySale> get sales => List.unmodifiable(_sales);

  List<DailySale> salesForDay(DateTime day) => _sales
      .where((s) => s.date.year == day.year && s.date.month == day.month && s.date.day == day.day)
      .toList();

  double get todayRevenue => salesForDay(DateTime.now()).fold(0.0, (sum, s) => sum + s.salePrice);
  double get todayMargin => salesForDay(DateTime.now()).fold(0.0, (sum, s) => sum + s.margin);

  Future<void> load() async {
    final db = await DBService.instance.database;
    final rows = await db.query('daily_sales', orderBy: 'date DESC');
    _sales
      ..clear()
      ..addAll(rows.map((r) => DailySale.fromMap(Map<String, dynamic>.from(r))));
    notifyListeners();
  }

  Future<void> addRow({
    required String productName,
    required double costPrice,
    required double salePrice,
    DateTime? date,
  }) async {
    if (productName.trim().isEmpty || costPrice < 0 || salePrice < 0) {
      throw ArgumentError('Invalid sale row');
    }
    final sale = DailySale(
      id: _uuid.v4(),
      date: date ?? DateTime.now(),
      productName: productName.trim(),
      costPrice: costPrice,
      salePrice: salePrice,
    );
    final db = await DBService.instance.database;
    await db.insert('daily_sales', sale.toMap());
    _sales.insert(0, sale);
    try {
      await SyncQueueService.instance.queueOperation(
        operation: 'create',
        tableName: 'daily_sales',
        documentId: sale.id,
        data: sale.toMap(),
      );
    } catch (e) {
      debugPrint('[Sales] Queue deferred: $e');
    }
    notifyListeners();
  }

  Future<void> deleteRow(String id) async {
    final db = await DBService.instance.database;
    await db.delete('daily_sales', where: 'id = ?', whereArgs: [id]);
    _sales.removeWhere((s) => s.id == id);
    try {
      await SyncQueueService.instance.queueOperation(
        operation: 'delete',
        tableName: 'daily_sales',
        documentId: id,
        data: const {},
      );
    } catch (e) {
      debugPrint('[Sales] Queue deferred: $e');
    }
    notifyListeners();
  }
}
