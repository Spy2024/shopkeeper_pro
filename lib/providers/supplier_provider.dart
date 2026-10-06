import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/product.dart';
import '../models/supplier.dart';
import '../services/db_service.dart';
import '../services/sync_queue_service.dart';
import 'inventory_provider.dart';

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
    if (value <= 0) throw ArgumentError('Amount must be positive');
    await _adjustSupplier(supplierId, stockDelta: value);
  }

  /// Records a payment made to a supplier (reduces the remaining balance).
  Future<void> recordPayment(String supplierId, double amount) async {
    if (amount <= 0) throw ArgumentError('Amount must be positive');
    final s = _suppliers.firstWhere((s) => s.id == supplierId);
    if (amount > s.remainingBalance) throw StateError('Payment exceeds outstanding balance');
    await _adjustSupplier(supplierId, paymentDelta: amount);
  }

  Future<void> _adjustSupplier(String supplierId,
      {double stockDelta = 0, double paymentDelta = 0}) async {
    final idx = _suppliers.indexWhere((s) => s.id == supplierId);
    if (idx == -1) throw StateError('Supplier not found');
    if (stockDelta < 0 || paymentDelta < 0) throw ArgumentError('Amounts cannot be negative');
    final current = _suppliers[idx];
    final updated = Supplier(
      id: current.id, name: current.name, phone: current.phone,
      totalStockReceivedValue: current.totalStockReceivedValue + stockDelta,
      totalPaymentsMade: current.totalPaymentsMade + paymentDelta);
    final db = await DBService.instance.database;
    await db.transaction((txn) async {
      await txn.update('suppliers', updated.toMap(),
          where: 'id = ?', whereArgs: [current.id]);
      if (stockDelta > 0) {
        await txn.insert('supplier_transactions', {
          'id': _uuid.v4(), 'supplierId': current.id, 'type': 'stock_received',
          'amount': stockDelta, 'date': DateTime.now().toIso8601String()});
      }
      if (paymentDelta > 0) {
        await txn.insert('supplier_transactions', {
          'id': _uuid.v4(), 'supplierId': current.id, 'type': 'payment',
          'amount': paymentDelta, 'date': DateTime.now().toIso8601String()});
      }
    });
    await SyncQueueService.instance.queueOperation(
      operation: 'update', tableName: 'suppliers', documentId: updated.id,
      data: updated.toMap());
    _suppliers[idx] = updated;
    notifyListeners();
  }

  Future<void> receiveOrder(String orderId, InventoryProvider inventory) async {
    final orderIndex = _orders.indexWhere((o) => o.id == orderId);
    if (orderIndex < 0) throw StateError('Purchase order not found');
    final order = _orders[orderIndex];
    if (order.status == 'received') throw StateError('Order already received');
    final supplier = _suppliers.firstWhere((s) => s.id == order.supplierId);
    final total = order.estimatedOrderTotal;
    final db = await DBService.instance.database;

    await db.transaction((txn) async {
      for (final item in order.items) {
        final matches = inventory.products.where((p) =>
            p.name.toLowerCase() == item.productName.toLowerCase());
        if (matches.isEmpty) throw StateError('Product not found');
        final product = matches.first;
        final changed = await txn.update('products',
            {'stockQuantity': product.stockQuantity + item.requiredQuantity},
            where: 'id = ?', whereArgs: [product.id]);
        if (changed != 1) throw StateError('Could not update inventory');
      }
      final updatedSupplier = Supplier(
        id: supplier.id, name: supplier.name, phone: supplier.phone,
        totalStockReceivedValue: supplier.totalStockReceivedValue + total,
        totalPaymentsMade: supplier.totalPaymentsMade);
      await txn.update('suppliers', updatedSupplier.toMap(),
          where: 'id = ?', whereArgs: [supplier.id]);
      await txn.insert('supplier_transactions', {
        'id': _uuid.v4(), 'supplierId': supplier.id, 'type': 'stock_received',
        'amount': total, 'date': DateTime.now().toIso8601String(), 'referenceId': order.id});
      await txn.update('supplier_orders', {'status': 'received'},
          where: 'id = ?', whereArgs: [order.id]);
    });

    for (final item in order.items) {
      final product = inventory.products.firstWhere(
          (p) => p.name.toLowerCase() == item.productName.toLowerCase());
      final newQuantity = product.stockQuantity + item.requiredQuantity;
      inventory.applyStockAfterTransaction(product.id, newQuantity);
      final updatedProduct = Product(
        id: product.id, name: product.name, category: product.category,
        stockQuantity: newQuantity, costPrice: product.costPrice,
        sellingPrice: product.sellingPrice, lowStockThreshold: product.lowStockThreshold);
      await SyncQueueService.instance.queueOperation(
        operation: 'update', tableName: 'products', documentId: product.id,
        data: updatedProduct.toMap());
    }
    final updatedSupplier = Supplier(
      id: supplier.id, name: supplier.name, phone: supplier.phone,
      totalStockReceivedValue: supplier.totalStockReceivedValue + total,
      totalPaymentsMade: supplier.totalPaymentsMade);
    _suppliers[_suppliers.indexWhere((s) => s.id == supplier.id)] = updatedSupplier;
    _orders[orderIndex] = SupplierOrder(
      id: order.id, supplierId: order.supplierId, supplierName: order.supplierName,
      date: order.date, items: order.items, status: 'received');
    await SyncQueueService.instance.queueOperation(
      operation: 'update', tableName: 'supplier_orders', documentId: order.id,
      data: {'id': order.id, 'supplierId': order.supplierId,
        'supplierName': order.supplierName, 'date': order.date.toIso8601String(),
        'status': 'received'});
    await SyncQueueService.instance.queueOperation(
      operation: 'update', tableName: 'suppliers', documentId: updatedSupplier.id,
      data: updatedSupplier.toMap());
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
      await SyncQueueService.instance.queueOperation(operation: 'create', tableName: 'supplier_orders/${order.id}/items', documentId: cloudId, data: {'cloudId': cloudId, 'orderId': order.id, 'productName': item.productName, 'requiredQuantity': item.requiredQuantity, 'estimatedPrice': item.estimatedPrice});
    }
    _orders.insert(0, order);
    _orderItemsCache[order.id] = items;
    notifyListeners();
    return order;
  }
}
