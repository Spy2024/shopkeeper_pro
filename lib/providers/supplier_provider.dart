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

void validateSupplierAmount(double amount) {
  if (!amount.isFinite || amount <= 0) {
    throw ArgumentError('Amount must be a finite positive number');
  }
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
    validateSupplierAmount(value);
    await _adjustSupplier(supplierId, stockDelta: value);
  }

  /// Records a payment made to a supplier (reduces the remaining balance).
  Future<void> recordPayment(String supplierId, double amount) async {
    validateSupplierAmount(amount);
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
    final db = await DBService.instance.database;
    late Supplier updated;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'suppliers',
        where: 'id = ?',
        whereArgs: [supplierId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Supplier no longer exists');
      final current = Supplier.fromMap(rows.single);
      final newStockReceived = current.totalStockReceivedValue + stockDelta;
      final newPaymentsMade = current.totalPaymentsMade + paymentDelta;
      if (!newStockReceived.isFinite || !newPaymentsMade.isFinite) {
        throw ArgumentError('Supplier totals exceed the supported amount range');
      }
      if (paymentDelta > 0 && paymentDelta > newStockReceived - current.totalPaymentsMade) {
        throw StateError('Payment exceeds outstanding balance');
      }
      updated = Supplier(
        id: current.id,
        name: current.name,
        phone: current.phone,
        totalStockReceivedValue: newStockReceived,
        totalPaymentsMade: newPaymentsMade,
      );
      final changed = await txn.update(
        'suppliers',
        updated.toMap(),
        where: 'id = ?',
        whereArgs: [current.id],
      );
      if (changed != 1) throw StateError('Supplier no longer exists');
      if (stockDelta > 0) {
        await txn.insert('supplier_transactions', {
          'id': _uuid.v4(),
          'supplierId': current.id,
          'type': 'stock_received',
          'amount': stockDelta,
          'date': DateTime.now().toIso8601String(),
        });
      }
      if (paymentDelta > 0) {
        await txn.insert('supplier_transactions', {
          'id': _uuid.v4(),
          'supplierId': current.id,
          'type': 'payment',
          'amount': paymentDelta,
          'date': DateTime.now().toIso8601String(),
        });
      }
    });

    // The transaction is the source of truth; reflect its exact totals before
    // best-effort queue persistence so concurrent payments cannot use stale state.
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
    late Supplier updatedSupplier;

    // Stock, supplier balance/transaction and order status commit together.
    await db.transaction((txn) async {
      final supplierRows = await txn.query(
        'suppliers',
        where: 'id = ?',
        whereArgs: [supplier.id],
        limit: 1,
      );
      if (supplierRows.isEmpty) throw StateError('Supplier no longer exists');
      final currentSupplier = Supplier.fromMap(supplierRows.single);
      final newStockReceivedTotal = currentSupplier.totalStockReceivedValue + total;
      if (!newStockReceivedTotal.isFinite) {
        throw StateError('Supplier total exceeds the supported amount range');
      }
      updatedSupplier = Supplier(
        id: currentSupplier.id,
        name: currentSupplier.name,
        phone: currentSupplier.phone,
        totalStockReceivedValue: newStockReceivedTotal,
        totalPaymentsMade: currentSupplier.totalPaymentsMade,
      );

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
    if (supplierId.trim().isEmpty || supplierName.trim().isEmpty) {
      throw ArgumentError('A supplier ID and name are required.');
    }
    if (items.isEmpty) {
      throw ArgumentError('A purchase order must contain at least one item.');
    }
    for (final item in items) {
      if (item.productName.trim().isEmpty ||
          item.requiredQuantity <= 0 ||
          !item.estimatedPrice.isFinite ||
          item.estimatedPrice < 0) {
        throw ArgumentError('Purchase order contains an invalid item.');
      }
    }

    final db = await DBService.instance.database;
    final order = SupplierOrder(
      id: _uuid.v4(),
      supplierId: supplierId,
      supplierName: supplierName,
      date: DateTime.now(),
      items: List.unmodifiable(items),
    );
    final childRows = <Map<String, dynamic>>[];

    // Keep the order and all child rows atomic locally. Each child gets a
    // stable cloud ID before commit, so a restart/offline period can be
    // recovered by the full-table sync even if queue insertion later fails.
    await db.transaction((txn) async {
      await txn.insert('supplier_orders', {
        'id': order.id,
        'supplierId': order.supplierId,
        'supplierName': order.supplierName,
        'date': order.date.toIso8601String(),
        'status': order.status,
      });
      for (final item in items) {
        final cloudId = _uuid.v4();
        await txn.insert('supplier_order_items', {
          'orderId': order.id,
          'productName': item.productName.trim(),
          'requiredQuantity': item.requiredQuantity,
          'estimatedPrice': item.estimatedPrice,
          'cloudId': cloudId,
        });
        childRows.add({
          'cloudId': cloudId,
          'orderId': order.id,
          'productName': item.productName.trim(),
          'requiredQuantity': item.requiredQuantity,
          'estimatedPrice': item.estimatedPrice,
        });
      }
    });

    // SQLite is authoritative. A queue error must not make a committed order
    // appear to fail; the next full sync uploads the saved order and children.
    await _queueSafely(
      operation: 'create',
      tableName: 'supplier_orders',
      documentId: order.id,
      data: {
        'id': order.id,
        'supplierId': order.supplierId,
        'supplierName': order.supplierName,
        'date': order.date.toIso8601String(),
        'status': order.status,
      },
    );
    for (final child in childRows) {
      await _queueSafely(
        operation: 'create',
        tableName: 'supplier_orders/${order.id}/items',
        documentId: child['cloudId'] as String,
        data: child,
      );
    }

    _orders.insert(0, order);
    _orderItemsCache[order.id] = List.unmodifiable(items);
    notifyListeners();
    return order;
  }
}
