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
    if (productName.trim().isEmpty || costPrice < 0 || salePrice < 0) {
      throw ArgumentError('Invalid sale');
    }
    final db = await DBService.instance.database;
    final rows = await db.query('daily_sales', orderBy: 'date DESC');
    _sales
      ..clear()
      ..addAll(rows.map((r) => DailySale.fromMap(r)));
    notifyListeners();
  }

  Future<void> addRow({
    required String productName,
    required double costPrice,
    required double salePrice,
    DateTime? date,
  }) async {
    final db = await DBService.instance.database;
    final sale = DailySale(
      id: _uuid.v4(),
      date: date ?? DateTime.now(),
      productName: productName,
      costPrice: costPrice,
      salePrice: salePrice,
    );
    await db.insert('daily_sales', sale.toMap());
    await SyncQueueService.instance.queueOperation(operation: 'create', tableName: 'sales', documentId: sale.id, data: sale.toMap());
    _sales.insert(0, sale);
    notifyListeners();
  }

  Future<void> deleteRow(String id) async {
    final db = await DBService.instance.database;
    await db.delete('daily_sales', where: 'id = ?', whereArgs: [id]);
    await SyncQueueService.instance.queueOperation(operation: 'delete', tableName: 'sales', documentId: id, data: {});
    _sales.removeWhere((s) => s.id == id);
    notifyListeners();
  }
}
