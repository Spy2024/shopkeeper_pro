import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/product.dart';
import '../models/supplier.dart';
import '../services/db_service.dart';
import '../services/sync_queue_service.dart';
import 'inventory_provider.dart';

/// Resolves order lines to stable product IDs and sums duplicate lines.
Map<String, int> aggregatePurchaseOrderQuantities({
  required List<SupplierOrderItem> items,
  required List<Product> products,
}) {
  if (items.isEmpty) throw StateError('Cannot receive an empty purchase order');
  final quantitiesByProductId = <String, int>{};
  for (final item in items) {
    if (item.requiredQuantity <= 0 ||
        !item.estimatedPrice.isFinite ||
        item.estimatedPrice < 0) {
      throw StateError('Purchase order contains an invalid quantity or price');
    }
    final normalizedName = item.productName.trim().toLowerCase();
    final matches = products.where(
      (p) => p.name.trim().toLowerCase() == normalizedName,
    );
    if (normalizedName.isEmpty || matches.length != 1) {
      throw StateError(
        matches.isEmpty
            ? 'Product not found: ${item.productName}'
            : 'Product name is ambiguous: ${item.productName}',
      );
    }
    final productId = matches.single.id;
    final nextQuantity = (quantitiesByProductId[productId] ?? 0) + item.requiredQuantity;
    if (nextQuantity <= 0) throw StateError('Purchase quantity overflow');
    quantitiesByProductId[productId] = nextQuantity;
  }
  return quantitiesByProductId;
}

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
    if (!value.isFinite || value <= 0) {
      throw ArgumentError('Amount must be a finite positive number');
    }
    await _adjustSupplier(supplierId, stockDelta: value);
  }

  /// Records a payment made to a supplier (reduces the remaining balance).
  Future<void> recordPayment(String supplierId, double amount) async {
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError('Amount must be a finite positive number');
    }
    final s = _suppliers.firstWhere((s) => s.id == supplierId);
    if (amount > s.remainingBalance) throw StateError('Payment exceeds outstanding balance');
    await _adjustSupplier(supplierId, paymentDelta: amount);
  }

  Future<void> _adjustSupplier(String supplierId,
      {double stockDelta = 0, double paymentDelta = 0}) async {
    final idx = _suppliers.indexWhere((s) => s.id == supplierId);
    if (idx == -1) throw StateError('Supplier not found');
    if (!stockDelta.isFinite ||
        !paymentDelta.isFinite ||
        stockDelta < 0 ||
        paymentDelta < 0) {
      throw ArgumentError('Amounts must be finite and non-negative');
    }
    final current = _suppliers[idx];
    final newStockReceived = current.totalStockReceivedValue + stockDelta;
    final newPaymentsMade = current.totalPaymentsMade + paymentDelta;
    if (!newStockReceived.isFinite || !newPaymentsMade.isFinite) {
      throw ArgumentError('Supplier totals exceed the supported amount range');
    }
    final updated = Supplier(
      id: current.id, name: current.name, phone: current.phone,
      totalStockReceivedValue: newStockReceived,
      totalPaymentsMade: newPaymentsMade);
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
    // The local transaction has committed; update the provider before
    // best-effort queue persistence so a sync outage cannot leave stale UI.
    _suppliers[idx] = updated;
    notifyListeners();
    try {
      await SyncQueueService.instance.queueOperation(
        operation: 'update',
        tableName: 'suppliers',
        documentId: updated.id,
        data: updated.toMap(),
      );
    } catch (error) {
      debugPrint('[SupplierProvider] Supplier totals saved locally; queue insert failed: $error');
    }
  }

  Future<void> receiveOrder(String orderId, InventoryProvider inventory) async {
    final orderIndex = _orders.indexWhere((o) => o.id == orderId);
    if (orderIndex < 0) throw StateError('Purchase order not found');
    final order = _orders[orderIndex];
    if (order.status == 'received') throw StateError('Order already received');
    if (order.items.isEmpty) throw StateError('Cannot receive an empty purchase order');

    final supplierIndex = _suppliers.indexWhere((s) => s.id == order.supplierId);
    if (supplierIndex < 0) throw StateError('Supplier not found');
    final supplier = _suppliers[supplierIndex];
    final total = order.estimatedOrderTotal;
    if (!total.isFinite || total < 0) {
      throw StateError('Purchase order total is invalid');
    }

    // Aggregate duplicate order lines so each product stock row is updated
    // once using the current database quantity.
    final quantitiesByProductId = aggregatePurchaseOrderQuantities(
      items: order.items,
      products: inventory.products,
    );
    final productsById = <String, Product>{
      for (final product in inventory.products)
        if (quantitiesByProductId.containsKey(product.id)) product.id: product,
    };

    final db = await DBService.instance.database;
    final newStockByProductId = <String, int>{};
    final newStockReceivedTotal = supplier.totalStockReceivedValue + total;
    if (!newStockReceivedTotal.isFinite) {
      throw StateError('Supplier total exceeds the supported amount range');
    }
    final updatedSupplier = Supplier(
      id: supplier.id,
      name: supplier.name,
      phone: supplier.phone,
      totalStockReceivedValue: newStockReceivedTotal,
      totalPaymentsMade: supplier.totalPaymentsMade,
    );

    // Stock, supplier balance/transaction and order status commit together.
    await db.transaction((txn) async {
      for (final entry in quantitiesByProductId.entries) {
        final rows = await txn.query(
          'products',
          columns: ['stockQuantity'],
          where: 'id = ?',
          whereArgs: [entry.key],
          limit: 1,
        );
        if (rows.isEmpty) {
          throw StateError('Product no longer exists: ${productsById[entry.key]!.name}');
        }
        final currentStock = (rows.single['stockQuantity'] as num).toInt();
        final newQuantity = currentStock + entry.value;
        if (newQuantity < currentStock) {
          throw StateError('Stock quantity overflow');
        }
        final changed = await txn.update(
          'products',
          {'stockQuantity': newQuantity},
          where: 'id = ?',
          whereArgs: [entry.key],
        );
        if (changed != 1) throw StateError('Could not update inventory');
        newStockByProductId[entry.key] = newQuantity;
      }

      final supplierChanged = await txn.update(
        'suppliers',
        updatedSupplier.toMap(),
        where: 'id = ?',
        whereArgs: [supplier.id],
      );
      if (supplierChanged != 1) throw StateError('Supplier no longer exists');

      await txn.insert('supplier_transactions', {
        'id': _uuid.v4(),
        'supplierId': supplier.id,
        'type': 'stock_received',
        'amount': total,
        'date': DateTime.now().toIso8601String(),
        'referenceId': order.id,
      });
      final orderChanged = await txn.update(
        'supplier_orders',
        {'status': 'received'},
        where: 'id = ? AND status != ?',
        whereArgs: [order.id, 'received'],
      );
      if (orderChanged != 1) {
        throw StateError('Purchase order was already received or no longer exists');
      }
    });

    // Reflect the committed database transaction in memory first. Queue
    // persistence is best-effort here: it must not make a committed receipt
    // look like a failed operation or leave the UI in the pre-receipt state.
    for (final entry in newStockByProductId.entries) {
      final product = productsById[entry.key]!;
      inventory.applyStockAfterTransaction(product.id, entry.value);
    }
    _suppliers[supplierIndex] = updatedSupplier;
    _orders[orderIndex] = SupplierOrder(
      id: order.id,
      supplierId: order.supplierId,
      supplierName: order.supplierName,
      date: order.date,
      items: order.items,
      status: 'received',
    );
    notifyListeners();

    for (final entry in newStockByProductId.entries) {
      final product = productsById[entry.key]!;
      final updatedProduct = Product(
        id: product.id,
        name: product.name,
        category: product.category,
        stockQuantity: entry.value,
        costPrice: product.costPrice,
        sellingPrice: product.sellingPrice,
        lowStockThreshold: product.lowStockThreshold,
        barcode: product.barcode,
        expiryDate: product.expiryDate,
      );
      await _queueSafely(
        operation: 'update',
        tableName: 'products',
        documentId: product.id,
        data: updatedProduct.toMap(),
      );
    }
    await _queueSafely(
      operation: 'update',
      tableName: 'supplier_orders',
      documentId: order.id,
      data: {
        'id': order.id,
        'supplierId': order.supplierId,
        'supplierName': order.supplierName,
        'date': order.date.toIso8601String(),
        'status': 'received',
      },
    );
    await _queueSafely(
      operation: 'update',
      tableName: 'suppliers',
      documentId: updatedSupplier.id,
      data: updatedSupplier.toMap(),
    );
  }

  Future<void> _queueSafely({
    required String operation,
    required String tableName,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    try {
      await SyncQueueService.instance.queueOperation(
        operation: operation,
        tableName: tableName,
        documentId: documentId,
        data: data,
      );
    } catch (error) {
      // The local SQLite transaction already committed. A future full sync
      // can upload current rows; never report the receipt as rolled back.
      debugPrint('[SupplierProvider] Local receipt committed; queue failed: $error');
    }
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
