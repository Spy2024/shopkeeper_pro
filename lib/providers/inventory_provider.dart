import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/product.dart';
import '../services/db_service.dart';
import '../services/sync_queue_service.dart';

class InventoryProvider extends ChangeNotifier {
  final List<Product> _products = [];
  final _uuid = const Uuid();

  List<Product> get products => List.unmodifiable(_products);
  List<Product> get lowOrOutOfStock =>
      _products.where((p) => p.isLowStock || p.isOutOfStock).toList();

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
      lowStockThreshold: current.lowStockThreshold);
    notifyListeners();
  }

  Future<void> addProduct({required String name, required String category, required int stockQuantity,
      required double costPrice, required double sellingPrice, int lowStockThreshold = 5}) async {
    final cleanName = name.trim();
    final cleanCategory = category.trim();
    if (cleanName.isEmpty) throw ArgumentError('Product name is required');
    if (stockQuantity < 0) throw ArgumentError('Stock cannot be negative');
    if (costPrice < 0 || sellingPrice < 0) throw ArgumentError('Prices cannot be negative');
    if (lowStockThreshold < 0) throw ArgumentError('Low-stock threshold cannot be negative');
    if (_products.any((p) => p.name.trim().toLowerCase() == cleanName.toLowerCase())) {
      throw StateError('A product with this name already exists');
    }
    final product = Product(id: _uuid.v4(), name: cleanName, category: cleanCategory,
      stockQuantity: stockQuantity, costPrice: costPrice, sellingPrice: sellingPrice, lowStockThreshold: lowStockThreshold);
    final db = await DBService.instance.database;
    await db.insert('products', product.toMap());
    await SyncQueueService.instance.queueOperation(operation: 'create', tableName: 'products',
      documentId: product.id, data: product.toMap());
    _products.add(product);
    notifyListeners();
  }

  Future<void> updateProduct(Product product) async {
    final cleanName = product.name.trim();
    if (cleanName.isEmpty) throw ArgumentError('Product name is required');
    if (product.stockQuantity < 0) throw ArgumentError('Stock cannot be negative');
    if (product.costPrice < 0 || product.sellingPrice < 0) throw ArgumentError('Prices cannot be negative');
    if (product.lowStockThreshold < 0) throw ArgumentError('Low-stock threshold cannot be negative');
    if (_products.any((p) => p.id != product.id && p.name.trim().toLowerCase() == cleanName.toLowerCase())) {
      throw StateError('A product with this name already exists');
    }
    final updated = Product(id: product.id, name: cleanName, category: product.category.trim(),
      stockQuantity: product.stockQuantity, costPrice: product.costPrice, sellingPrice: product.sellingPrice,
      lowStockThreshold: product.lowStockThreshold);
    final db = await DBService.instance.database;
    final changed = await db.update('products', updated.toMap(), where: 'id = ?', whereArgs: [updated.id]);
    if (changed != 1) throw StateError('Product not found');
    await SyncQueueService.instance.queueOperation(operation: 'update', tableName: 'products',
      documentId: updated.id, data: updated.toMap());
    final idx = _products.indexWhere((p) => p.id == updated.id);
    if (idx != -1) _products[idx] = updated;
    notifyListeners();
  }

  Future<void> deleteProduct(String id) async {
    if (id.trim().isEmpty) throw ArgumentError('Product id is required');
    final db = await DBService.instance.database;
    final changed = await db.delete('products', where: 'id = ?', whereArgs: [id]);
    if (changed == 0) return;
    await SyncQueueService.instance.queueOperation(operation: 'delete', tableName: 'products', documentId: id, data: {});
    _products.removeWhere((p) => p.id == id);
    notifyListeners();
  }

  Future<void> deductStock(String productId, int quantitySold) async {
    if (quantitySold <= 0) throw ArgumentError('Quantity must be positive');
    final product = findById(productId);
    if (product == null) throw StateError('Product not found');
    if (product.stockQuantity < quantitySold) throw StateError('Insufficient stock');
    applyStockAfterTransaction(productId, product.stockQuantity - quantitySold);
  }

  List<Product> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return products;
    return _products.where((p) => p.name.toLowerCase().contains(q)).toList();
  }
}