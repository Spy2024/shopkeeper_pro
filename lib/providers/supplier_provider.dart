import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/supplier.dart';
import '../services/db_service.dart';
import '../services/sync_queue_service.dart';

class SupplierProvider extends ChangeNotifier {
  final List<Supplier> _suppliers = [];
  final List<SupplierOrder> _orders = [];
  final Map<String, List<SupplierOrderItem>> _orderItemsCache = {};
  final _uuid = const Uuid();

  List<Supplier> get suppliers => List.unmodifiable(_suppliers);
  List<SupplierOrder> get orders => List.unmodifiable(_orders);

  Future<void> load() async {
    final db = await DBService.instance.database;
    final supplierRows = await db.query('suppliers', orderBy: 'name COLLATE NOCASE');
    _suppliers
      ..clear()
      ..addAll(supplierRows.map((r) => Supplier.fromMap(r)));

    final orderRows = await db.query('supplier_orders', orderBy: 'date DESC');
    _orders.clear();
    _orderItemsCache.clear();
    for (final row in orderRows) {
      final itemRows =
          await db.query('supplier_order_items', where: 'orderId = ?', whereArgs: [row['id']]);
      final items = itemRows
          .map((r) => SupplierOrderItem(
                productName: r['productName'] as String,
                requiredQuantity: r['requiredQuantity'] as int,
                estimatedPrice: (r['estimatedPrice'] as num).toDouble(),
              ))
          .toList();
      final order = SupplierOrder(
        id: row['id'] as String,
        supplierId: row['supplierId'] as String,
        supplierName: row['supplierName'] as String,
        date: DateTime.parse(row['date'] as String),
        items: items,
        status: row['status'] as String,
      );
      _orders.add(order);
      _orderItemsCache[order.id] = items;
    }
    notifyListeners();
  }

  Future<void> addSupplier(String name, String phone) async {
    final db = await DBService.instance.database;
    final supplier = Supplier(id: _uuid.v4(), name: name, phone: phone);
    await db.insert('suppliers', supplier.toMap());
    await SyncQueueService.instance.queueOperation(operation: 'create', tableName: 'suppliers', documentId: supplier.id, data: supplier.toMap());
    _suppliers.add(supplier);
    notifyListeners();
  }

  /// Records new stock received from a supplier (increases what's owed).
  Future<void> recordStockReceived(String supplierId, double value) async {
    await _adjustSupplier(supplierId, stockDelta: value);
  }

  /// Records a payment made to a supplier (reduces the remaining balance).
  Future<void> recordPayment(String supplierId, double amount) async {
    await _adjustSupplier(supplierId, paymentDelta: amount);
  }

  Future<void> _adjustSupplier(String supplierId,
      {double stockDelta = 0, double paymentDelta = 0}) async {
    final idx = _suppliers.indexWhere((s) => s.id == supplierId);
    if (idx == -1) return;
    final s = _suppliers[idx];
    final updated = Supplier(
      id: s.id,
      name: s.name,
      phone: s.phone,
      totalStockReceivedValue: s.totalStockReceivedValue + stockDelta,
      totalPaymentsMade: s.totalPaymentsMade + paymentDelta,
    );
    final db = await DBService.instance.database;
    await db.update('suppliers', updated.toMap(), where: 'id = ?', whereArgs: [s.id]);
    await SyncQueueService.instance.queueOperation(operation: 'update', tableName: 'suppliers', documentId: updated.id, data: updated.toMap());
    _suppliers[idx] = updated;
    notifyListeners();
  }

  Future<SupplierOrder> createOrder(
      String supplierId, String supplierName, List<SupplierOrderItem> items) async {
    final db = await DBService.instance.database;
    final order = SupplierOrder(
      id: _uuid.v4(),
      supplierId: supplierId,
      supplierName: supplierName,
      date: DateTime.now(),
      items: items,
    );
    await db.insert('supplier_orders', {
      'id': order.id,
      'supplierId': order.supplierId,
      'supplierName': order.supplierName,
      'date': order.date.toIso8601String(),
      'status': order.status,
    });
    await SyncQueueService.instance.queueOperation(operation: 'create', tableName: 'supplier_orders', documentId: order.id, data: {'id': order.id, 'supplierId': order.supplierId, 'supplierName': order.supplierName, 'date': order.date.toIso8601String(), 'status': order.status});
    for (final item in items) {
      final itemId = await db.insert('supplier_order_items', {
        'orderId': order.id,
        'productName': item.productName,
        'requiredQuantity': item.requiredQuantity,
        'estimatedPrice': item.estimatedPrice,
      });
      final cloudId = _uuid.v4();
      await db.update('supplier_order_items', {'cloudId': cloudId}, where: 'id = ?', whereArgs: [itemId]);
      await SyncQueueService.instance.queueOperation(operation: 'create', tableName: 'supplier_orders/' + order.id + '/items', documentId: cloudId, data: {'cloudId': cloudId, 'orderId': order.id, 'productName': item.productName, 'requiredQuantity': item.requiredQuantity, 'estimatedPrice': item.estimatedPrice});
    }
    _orders.insert(0, order);
    _orderItemsCache[order.id] = items;
    notifyListeners();
    return order;
  }
}
