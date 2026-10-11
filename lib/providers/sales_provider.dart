import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/daily_sale.dart';
import '../services/db_service.dart';
import '../services/sync_queue_service.dart';

void validateManualSaleInput({
  required String productName,
  required double costPrice,
  required double salePrice,
  required int quantity,
}) {
  if (productName.trim().isEmpty ||
      !costPrice.isFinite ||
      !salePrice.isFinite ||
      costPrice < 0 ||
      salePrice < 0 ||
      quantity <= 0) {
    throw ArgumentError('Invalid sale');
  }
}

class SalesProvider extends ChangeNotifier {
  final List<DailySale> _sales = [];
  final _uuid = const Uuid();
  List<DailySale> get sales => List.unmodifiable(_sales);
  List<DailySale> salesForDay(DateTime day) => _sales.where((s) => s.date.year == day.year && s.date.month == day.month && s.date.day == day.day).toList();
  double get todayRevenue => salesForDay(DateTime.now()).fold(0.0, (sum, s) => sum + s.revenue);
  double get todayMargin => salesForDay(DateTime.now()).fold(0.0, (sum, s) => sum + s.margin);

  Future<void> load() async {
    final db = await DBService.instance.database;
    final rows = await db.query('daily_sales', orderBy: 'date DESC');
    _sales..clear()..addAll(rows.map((r) => DailySale.fromMap(r)));
    notifyListeners();
  }

  Future<void> addRow({required String productName, required double costPrice, required double salePrice, int quantity = 1, DateTime? date}) async {
    final cleanName = productName.trim();
    validateManualSaleInput(
      productName: cleanName,
      costPrice: costPrice,
      salePrice: salePrice,
      quantity: quantity,
    );
    final db = await DBService.instance.database;
    final sale = DailySale(id: _uuid.v4(), date: date ?? DateTime.now(), productName: cleanName,
      costPrice: costPrice, salePrice: salePrice, quantity: quantity, source: 'manual');
    await db.insert('daily_sales', sale.toMap());
    try {
      await SyncQueueService.instance.queueOperation(
        operation: 'create',
        tableName: 'sales',
        documentId: sale.id,
        data: sale.toMap(),
      );
    } catch (error) {
      // SQLite has committed the local sale. A queue failure must not make
      // the UI report failure for a record that is already saved.
      debugPrint('[SalesProvider] Sale saved locally; queue insert failed: $error');
    }
    _sales.insert(0, sale);
    notifyListeners();
  }

  Future<void> deleteRow(String id) async {
    if (id.trim().isEmpty) throw ArgumentError('Sale id is required');
    final db = await DBService.instance.database;
    final exists = await db.query(
      'daily_sales',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (exists.isEmpty) return;
    // Persist the tombstone before local deletion; if the queue cannot be
    // saved, keep the row so a later sync cannot resurrect a deleted sale.
    await SyncQueueService.instance.queueOperation(
      operation: 'delete',
      tableName: 'sales',
      documentId: id,
      data: const {},
    );
    final changed = await db.delete('daily_sales', where: 'id = ?', whereArgs: [id]);
    if (changed == 0) return;
    _sales.removeWhere((s) => s.id == id);
    notifyListeners();
  }
}