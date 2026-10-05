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
    _products
      ..clear()
      ..addAll(rows.map((r) => Product.fromMap(r)));
    notifyListeners();
  }

  Future<void> addProduct({
    required String name,
    required String category,
    required int stockQuantity,
    required double costPrice,
    required double sellingPrice,
    int lowStockThreshold = 5,
  }) async {
    final db = await DBService.instance.database;
    final product = Product(
      id: _uuid.v4(),
      name: cleanName,
      category: category,
      stockQuantity: stockQuantity,
      costPrice: costPrice,
      sellingPrice: sellingPrice,
      lowStockThreshold: lowStockThreshold,
    );
    if (_products.any((p) => p.name.toLowerCase() == cleanName.toLowerCase())) throw StateError('A product with this name already exists');
    await db.insert('products', product.toMap());
    await SyncQueueService.instance.queueOperation(operation: 'create', tableName: 'products', documentId: product.id, data: product.toMap());
    _products.add(product);
    notifyListeners();
  }

  Future<void> updateProduct(Product product) async {
    final db = await DBService.instance.database;
    await db.update('products', product.toMap(), where: 'id = ?', whereArgs: [product.id]);
    await SyncQueueService.instance.queueOperation(operation: 'update', tableName: 'products', documentId: product.id, data: product.toMap());
    final idx = _products.indexWhere((p) => p.id == product.id);
    if (idx != -1) _products[idx] = product;
    notifyListeners();
  }

  Future<void> deleteProduct(String id) async {
    final db = await DBService.instance.database;
    await db.delete('products', where: 'id = ?', whereArgs: [id]);
    await SyncQueueService.instance.queueOperation(operation: 'delete', tableName: 'products', documentId: id, data: {});
    _products.removeWhere((p) => p.id == id);
    notifyListeners();
  }

  /// Deducts stock after a POS sale. Call once per line item sold.
  Future<void> deductStock(String productId, int quantitySold) async {
    final idx = _products.indexWhere((p) => p.id == productId);
    if (idx == -1) return;
    final p = _products[idx];
    final updated = Product(
      id: p.id,
      name: p.name,
      category: p.category,
      stockQuantity: (p.stockQuantity - quantitySold).clamp(0, 1 << 31),
      costPrice: p.costPrice,
      sellingPrice: p.sellingPrice,
      lowStockThreshold: p.lowStockThreshold,
    );
    await updateProduct(updated);
  }

  List<Product> search(String query) {
    if (query.trim().isEmpty) return products;
    final q = query.toLowerCase();
    return _products.where((p) => p.name.toLowerCase().contains(q)).toList();
  }
}
