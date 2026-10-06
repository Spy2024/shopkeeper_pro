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
      ..addAll(supplierRows.map((r) => Supplier.fromMap(Map<String, dynamic>.from(r))));

    final orderRows = await db.query('supplier_orders', orderBy: 'date DESC');
    _orders.clear();
    _orderItemsCache.clear();
    for (final row in orderRows) {
      final itemRows = await db.query(
        'supplier_order_items',
        where: 'orderId = ?',
        whereArgs: [row['id']],
      );
      final items = itemRows
          .map((r) => SupplierOrderItem(
                productName: r['productName'] as String,
                requiredQuantity: (r['requiredQuantity'] as num).toInt(),
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
    if (name.trim().isEmpty || phone.trim().isEmpty) {
      throw ArgumentError('Supplier name and phone are required');
    }
    final supplier = Supplier(id: _uuid.v4(), name: name.trim(), phone: phone.trim());
    final db = await DBService.instance.database;
    await db.insert('suppliers', supplier.toMap());
    _suppliers.add(supplier);
    try {
      await SyncQueueService.instance.queueOperation(
        operation: 'create',
        tableName: 'suppliers',
        documentId: supplier.id,
        data: supplier.toMap(),
      );
    } catch (e) {
      debugPrint('[Supplier] Queue deferred: $e');
    }
    notifyListeners();
  }

  Future<void> recordStockReceived(String supplierId, double value) async {
    if (value <= 0) throw ArgumentError('Value must be positive');
    await _adjustSupplier(supplierId, stockDelta: value);
  }

  Future<void> recordPayment(String supplierId, double amount) async {
    if (amount <= 0) throw ArgumentError('Amount must be positive');
    await _adjustSupplier(supplierId, paymentDelta: amount);
  }

  Future<void> _adjustSupplier(
    String supplierId, {
    double stockDelta = 0,
    double paymentDelta = 0,
  }) async {
    final idx = _suppliers.indexWhere((s) => s.id == supplierId);
    if (idx == -1) throw StateError('Supplier not found: $supplierId');

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
    _suppliers[idx] = updated;

    try {
      await SyncQueueService.instance.queueOperation(
        operation: 'update',
        tableName: 'suppliers',
        documentId: updated.id,
        data: updated.toMap(),
      );
    } catch (e) {
      debugPrint('[Supplier] Queue deferred: $e');
    }
    notifyListeners();
  }

  Future<SupplierOrder> createOrder(
    String supplierId,
    String supplierName,
    List<SupplierOrderItem> items,
  ) async {
    if (supplierId.isEmpty || supplierName.trim().isEmpty || items.isEmpty) {
      throw ArgumentError('Supplier and order items are required');
    }
    for (final item in items) {
      if (item.productName.trim().isEmpty ||
          item.requiredQuantity <= 0 ||
          item.estimatedPrice < 0) {
        throw ArgumentError('Invalid supplier order item');
      }
    }

    final order = SupplierOrder(
      id: _uuid.v4(),
      supplierId: supplierId,
      supplierName: supplierName.trim(),
      date: DateTime.now(),
      items: List<SupplierOrderItem>.unmodifiable(items),
    );

    final db = await DBService.instance.database;
    await db.transaction((txn) async {
      await txn.insert('supplier_orders', {
        'id': order.id,
        'supplierId': order.supplierId,
        'supplierName': order.supplierName,
        'date': order.date.toIso8601String(),
        'status': order.status,
      });
      for (final item in order.items) {
        await txn.insert('supplier_order_items', {
          'orderId': order.id,
          'productName': item.productName.trim(),
          'requiredQuantity': item.requiredQuantity,
          'estimatedPrice': item.estimatedPrice,
        });
      }
    });

    _orders.insert(0, order);
    _orderItemsCache[order.id] = order.items;

    try {
      await SyncQueueService.instance.queueOperation(
        operation: 'create',
        tableName: 'supplier_orders',
        documentId: order.id,
        data: order.toSyncMap(),
      );
    } catch (e) {
      debugPrint('[Supplier] Queue deferred: $e');
    }

    notifyListeners();
    return order;
  }
}
