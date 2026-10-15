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
      ..addAll(rows.map((r) => Product.fromMap(Map<String, dynamic>.from(r))));
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
    if (name.trim().isEmpty || category.trim().isEmpty || stockQuantity < 0 ||
        costPrice < 0 || sellingPrice < 0 || lowStockThreshold < 0) {
      throw ArgumentError('Invalid product values');
    }

    final product = Product(
      id: _uuid.v4(),
      name: name.trim(),
      category: category.trim(),
      stockQuantity: stockQuantity,
      costPrice: costPrice,
      sellingPrice: sellingPrice,
      lowStockThreshold: lowStockThreshold,
    );

    final db = await DBService.instance.database;
    await db.insert('products', product.toMap());
    _products.add(product);

    try {
      await SyncQueueService.instance.queueOperation(
        operation: 'create',
        tableName: 'products',
        documentId: product.id,
        data: product.toMap(),
      );
    } catch (e) {
      debugPrint('[Inventory] Queue deferred: $e');
    }
    notifyListeners();
  }

  Future<void> updateProduct(Product product) async {
    if (product.name.trim().isEmpty || product.category.trim().isEmpty ||
        product.stockQuantity < 0 || product.costPrice < 0 ||
        product.sellingPrice < 0 || product.lowStockThreshold < 0) {
      throw ArgumentError('Invalid product values');
    }

    final normalized = Product(
      id: product.id,
      name: product.name.trim(),
      category: product.category.trim(),
      stockQuantity: product.stockQuantity,
      costPrice: product.costPrice,
      sellingPrice: product.sellingPrice,
      lowStockThreshold: product.lowStockThreshold,
    );

    final db = await DBService.instance.database;
    final changed = await db.update(
      'products',
      normalized.toMap(),
      where: 'id = ?',
      whereArgs: [normalized.id],
    );
    if (changed != 1) throw StateError('Product not found: ${normalized.id}');

    final idx = _products.indexWhere((p) => p.id == normalized.id);
    if (idx != -1) _products[idx] = normalized;

    try {
      await SyncQueueService.instance.queueOperation(
        operation: 'update',
        tableName: 'products',
        documentId: normalized.id,
        data: normalized.toMap(),
      );
    } catch (e) {
      debugPrint('[Inventory] Queue deferred: $e');
    }
    notifyListeners();
  }

  Future<void> deleteProduct(String id) async {
    final db = await DBService.instance.database;
    await db.delete('products', where: 'id = ?', whereArgs: [id]);
    _products.removeWhere((p) => p.id == id);

    try {
      await SyncQueueService.instance.queueOperation(
        operation: 'delete',
        tableName: 'products',
        documentId: id,
        data: const {},
      );
    } catch (e) {
      debugPrint('[Inventory] Queue deferred: $e');
    }
    notifyListeners();
  }

  Future<void> deductStock(String productName, int quantitySold) async {
    if (quantitySold <= 0) throw ArgumentError('quantitySold must be positive');
    final matches = _products.where((p) => p.name == productName);
    if (matches.isEmpty) throw StateError('Product not found: ${productName}');
    final product = matches.first;
    final remaining = product.stockQuantity - quantitySold;
    if (remaining < 0) throw StateError('Insufficient stock for ${productName}');

    await updateProduct(Product(
      id: product.id,
      name: product.name,
      category: product.category,
      stockQuantity: remaining,
      costPrice: product.costPrice,
      sellingPrice: product.sellingPrice,
      lowStockThreshold: product.lowStockThreshold,
    ));
  }

  List<Product> search(String query) {
    if (query.trim().isEmpty) return products;
    final q = query.toLowerCase().trim();
    return _products.where((p) => p.name.toLowerCase().contains(q)).toList();
  }
}
