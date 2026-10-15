import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/product.dart';
import '../services/db_service.dart';
import '../services/sync_queue_service.dart';

void validateProductValues({
  required int stockQuantity,
  required double costPrice,
  required double sellingPrice,
  required int lowStockThreshold,
}) {
  if (stockQuantity < 0) throw ArgumentError('Stock cannot be negative');
  if (!costPrice.isFinite || !sellingPrice.isFinite) {
    throw ArgumentError('Prices must be finite numbers');
  }
  if (costPrice < 0 || sellingPrice < 0) {
    throw ArgumentError('Prices cannot be negative');
  }
  if (lowStockThreshold < 0) {
    throw ArgumentError('Low-stock threshold cannot be negative');
  }
}

class InventoryProvider extends ChangeNotifier {
  final List<Product> _products = [];
  final _uuid = const Uuid();

  List<Product> get products => List.unmodifiable(_products);
  List<Product> get lowOrOutOfStock =>
      _products.where((p) => p.isLowStock || p.isOutOfStock).toList();
  List<Product> get expiredProducts => _products.where((p) => p.isExpired).toList();
  List<Product> get expiringSoonProducts =>
      _products.where((p) => p.expiresWithin30Days).toList();

  Future<void> load() async {
    final db = await DBService.instance.database;
    final rows = await db.query('products', orderBy: 'name COLLATE NOCASE');
    _products..clear()..addAll(rows.map((r) => Product.fromMap(r)));
    notifyListeners();
  }

  Product? findById(String id) {
    for (final product in _products) {
      if (product.id == id) return product;
    }
    return null;
  }

  void applyStockAfterTransaction(String productId, int stockQuantity) {
    final index = _products.indexWhere((p) => p.id == productId);
    if (index == -1) return;
    final current = _products[index];
    _products[index] = Product(id: current.id, name: current.name, category: current.category,
      stockQuantity: stockQuantity, costPrice: current.costPrice, sellingPrice: current.sellingPrice,
      lowStockThreshold: current.lowStockThreshold, barcode: current.barcode,
      expiryDate: current.expiryDate);
    notifyListeners();
  }

  Future<void> addProduct({required String name, required String category, required int stockQuantity,
      required double costPrice, required double sellingPrice, int lowStockThreshold = 5,
      String? barcode, DateTime? expiryDate}) async {
    final cleanName = name.trim();
    final cleanCategory = category.trim();
    final cleanBarcode = barcode?.trim().isEmpty == true ? null : barcode?.trim();
    if (cleanName.isEmpty) throw ArgumentError('Product name is required');
    validateProductValues(
      stockQuantity: stockQuantity,
      costPrice: costPrice,
      sellingPrice: sellingPrice,
      lowStockThreshold: lowStockThreshold,
    );
    if (_products.any((p) => p.name.trim().toLowerCase() == cleanName.toLowerCase())) {
      throw StateError('A product with this name already exists');
    }
    if (cleanBarcode != null && _products.any((p) => p.barcode == cleanBarcode)) {
      throw StateError('A product with this barcode already exists');
    }
    final product = Product(id: _uuid.v4(), name: cleanName, category: cleanCategory,
      stockQuantity: stockQuantity, costPrice: costPrice, sellingPrice: sellingPrice,
      lowStockThreshold: lowStockThreshold, barcode: cleanBarcode, expiryDate: expiryDate);
    final db = await DBService.instance.database;
    await db.insert('products', product.toMap());
    try {
      await SyncQueueService.instance.queueOperation(
        operation: 'create',
        tableName: 'products',
        documentId: product.id,
        data: product.toMap(),
      );
    } catch (e) {
      // Keep the committed local change visible. The next full sync can upload
      // this product from SQLite even if the queue insert temporarily fails.
      debugPrint('[InventoryProvider] Product saved locally; queue insert failed: $e');
    }
    _products.add(product);
    notifyListeners();
  }

  Future<void> updateProduct(Product product) async {
    final cleanName = product.name.trim();
    if (cleanName.isEmpty) throw ArgumentError('Product name is required');
    validateProductValues(
      stockQuantity: product.stockQuantity,
      costPrice: product.costPrice,
      sellingPrice: product.sellingPrice,
      lowStockThreshold: product.lowStockThreshold,
    );
    if (_products.any((p) => p.id != product.id && p.name.trim().toLowerCase() == cleanName.toLowerCase())) {
      throw StateError('A product with this name already exists');
    }
    final cleanBarcode = product.barcode?.trim().isEmpty == true ? null : product.barcode?.trim();
    if (cleanBarcode != null && _products.any((p) => p.id != product.id && p.barcode == cleanBarcode)) {
      throw StateError('A product with this barcode already exists');
    }
    final updated = Product(id: product.id, name: cleanName, category: product.category.trim(),
      stockQuantity: product.stockQuantity, costPrice: product.costPrice, sellingPrice: product.sellingPrice,
      lowStockThreshold: product.lowStockThreshold, barcode: cleanBarcode, expiryDate: product.expiryDate);
    final db = await DBService.instance.database;
    final changed = await db.update('products', updated.toMap(), where: 'id = ?', whereArgs: [updated.id]);
    if (changed != 1) throw StateError('Product not found');
    try {
      await SyncQueueService.instance.queueOperation(
        operation: 'update',
        tableName: 'products',
        documentId: updated.id,
        data: updated.toMap(),
      );
    } catch (e) {
      // SQLite is the source of truth; a later full sync can upload this row.
      debugPrint('[InventoryProvider] Product updated locally; queue insert failed: $e');
    }
    final idx = _products.indexWhere((p) => p.id == updated.id);
    if (idx != -1) _products[idx] = updated;
    notifyListeners();
  }

  Future<void> deleteProduct(String id) async {
    final cleanId = id.trim();
    if (cleanId.isEmpty) throw ArgumentError('Product id is required');
    final db = await DBService.instance.database;
    var deleted = false;
    await db.transaction((txn) async {
      final productRows = await txn.query(
        'products',
        columns: ['stockQuantity'],
        where: 'id = ?',
        whereArgs: [cleanId],
        limit: 1,
      );
      if (productRows.isEmpty) return;
      final stockQuantity = (productRows.single['stockQuantity'] as num).toInt();
      if (stockQuantity > 0) {
        throw StateError('Cannot delete a product with stock. Record a stock adjustment or write-off first.');
      }
      final branchRows = await txn.query(
        'branch_stock',
        columns: ['quantity'],
        where: 'productId = ?',
        whereArgs: [cleanId],
      );
      if (branchRows.any((row) => (row['quantity'] as num).toInt() > 0)) {
        throw StateError('Cannot delete a product with branch stock allocations.');
      }
      final transferRows = await txn.query(
        'stock_transfers',
        columns: ['id'],
        where: 'productId = ?',
        whereArgs: [cleanId],
        limit: 1,
      );
      if (transferRows.isNotEmpty) {
        throw StateError('Cannot delete a product with transfer history; archive support is required.');
      }

      // Zero-quantity allocation rows no longer need to block product deletion.
      await txn.delete('branch_stock', where: 'productId = ?', whereArgs: [cleanId]);
      final changed = await txn.delete('products', where: 'id = ?', whereArgs: [cleanId]);
      if (changed != 1) return;

      // Save the delete tombstone in the same transaction as the local delete.
      // This prevents a cloud delete from being queued when the local delete fails.
      final now = DateTime.now().microsecondsSinceEpoch;
      await txn.insert('sync_queue', {
        'id': 'products_${cleanId}_$now',
        'operation': 'delete',
        'tableName': 'products',
        'documentId': cleanId,
        'data': jsonEncode(<String, dynamic>{}),
        'timestamp': now,
        'synced': 0,
      });
      deleted = true;
    });

    _products.removeWhere((product) => product.id == cleanId);
    notifyListeners();
    if (deleted) {
      try {
        await SyncQueueService.instance.reloadPendingQueue();
      } catch (e) {
        // The durable tombstone remains in SQLite and will be reloaded by the next sync.
        debugPrint('[InventoryProvider] Product deleted locally; queue refresh failed: $e');
      }
    }
  }

  Future<void> deductStock(String productId, int quantitySold) async {
    if (quantitySold <= 0) throw ArgumentError('Quantity must be positive');
    final product = findById(productId);
    if (product == null) throw StateError('Product not found');
    if (product.stockQuantity < quantitySold) throw StateError('Insufficient stock');
    final updated = Product(id: product.id, name: product.name, category: product.category,
      stockQuantity: product.stockQuantity - quantitySold, costPrice: product.costPrice,
      sellingPrice: product.sellingPrice, lowStockThreshold: product.lowStockThreshold,
      barcode: product.barcode, expiryDate: product.expiryDate);
    await updateProduct(updated);
  }

  List<Product> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return products;
    return _products.where((p) => p.name.toLowerCase().contains(q) ||
        (p.barcode?.toLowerCase().contains(q) ?? false)).toList();
  }
}