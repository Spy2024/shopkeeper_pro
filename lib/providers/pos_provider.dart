import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/bill.dart';
import '../models/product.dart';
import '../models/daily_sale.dart';
import '../services/db_service.dart';
import '../services/sync_queue_service.dart';
import 'inventory_provider.dart';

class PosProvider extends ChangeNotifier {
  final List<BillItem> cart = [];
  double discount = 0;
  double taxPercent = 0;
  String? customerName;
  final _uuid = const Uuid();
  final List<Bill> savedBills = [];
  final Map<String, List<BillItem>> _billItemsCache = {};

  double get subtotal => cart.fold(0.0, (sum, i) => sum + i.lineTotal);
  double get taxableSubtotal => (subtotal - discount).clamp(0.0, double.infinity).toDouble();
  double get taxAmount => taxableSubtotal * (taxPercent / 100);
  double get grandTotal => taxableSubtotal + taxAmount;

  void addItem(String productName, int quantity, double unitPrice, {String? productId}) {
    final cleanName = productName.trim();
    if (cleanName.isEmpty || quantity <= 0 || unitPrice <= 0) throw ArgumentError('Invalid cart item');
    final existingIndex = productId == null ? -1 : cart.indexWhere((item) => item.productId == productId);
    if (existingIndex >= 0) {
      final existing = cart[existingIndex];
      cart[existingIndex] = BillItem(productId: existing.productId, productName: existing.productName,
        quantity: existing.quantity + quantity, unitPrice: unitPrice);
    } else {
      cart.add(BillItem(productId: productId, productName: cleanName, quantity: quantity, unitPrice: unitPrice));
    }
    notifyListeners();
  }

  void removeItem(int index) {
    if (index < 0 || index >= cart.length) return;
    cart.removeAt(index);
    notifyListeners();
  }

  void setDiscount(double value) {
    if (value < 0) throw ArgumentError('Discount cannot be negative');
    discount = value > subtotal ? subtotal : value;
    notifyListeners();
  }

  void setTax(double percent) {
    if (percent < 0 || percent > 100) throw ArgumentError('Tax must be between 0 and 100');
    taxPercent = percent;
    notifyListeners();
  }

  void setCustomerName(String? name) {
    final clean = name?.trim();
    customerName = clean == null || clean.isEmpty ? null : clean;
    notifyListeners();
  }

  void clearCart() {
    cart.clear(); discount = 0; taxPercent = 0; customerName = null; notifyListeners();
  }

  Future<Bill> checkout(InventoryProvider inventory) async {
    if (cart.isEmpty) throw StateError('Cart is empty');
    if (discount < 0 || discount > subtotal) throw StateError('Invalid discount');
    if (taxPercent < 0 || taxPercent > 100) throw StateError('Invalid tax');

    final productsById = <String, Product>{};
    final quantitiesById = <String, int>{};
    final itemProducts = <BillItem, Product>{};
    for (final item in cart) {
      Product? product = item.productId == null ? null : inventory.findById(item.productId!);
      if (product == null) {
        for (final candidate in inventory.products) {
          if (candidate.name.trim().toLowerCase() == item.productName.trim().toLowerCase()) { product = candidate; break; }
        }
      }
      if (product == null) throw StateError('Product not found: ' + item.productName);
      if (item.quantity <= 0 || item.unitPrice <= 0) throw StateError('Invalid quantity or price');
      productsById[product.id] = product;
      quantitiesById[product.id] = (quantitiesById[product.id] ?? 0) + item.quantity;
      itemProducts[item] = product;
    }
    for (final entry in quantitiesById.entries) {
      final product = productsById[entry.key]!;
      if (product.stockQuantity < entry.value) throw StateError('Insufficient stock for ' + product.name);
    }

    final db = await DBService.instance.database;
    final bill = Bill(id: _uuid.v4(), date: DateTime.now(), customerName: customerName,
      items: List.unmodifiable(cart), discount: discount, taxPercent: taxPercent);
    final newQuantities = <String, int>{};
    final itemCloudIds = List<String>.generate(bill.items.length, (_) => _uuid.v4());

    await db.transaction((txn) async {
      await txn.insert('bills', bill.toMap());
      for (var i = 0; i < bill.items.length; i++) {
        await txn.insert('bill_items', {...bill.items[i].toMap(), 'billId': bill.id, 'cloudId': itemCloudIds[i]});
      }
      for (final entry in quantitiesById.entries) {
        final product = productsById[entry.key]!;
        final newQty = product.stockQuantity - entry.value;
        final changed = await txn.update('products', {'stockQuantity': newQty},
          where: 'id = ? AND stockQuantity >= ?', whereArgs: [product.id, entry.value]);
        if (changed != 1) throw StateError('Stock changed. Please retry checkout.');
        newQuantities[product.id] = newQty;
      }
      final discountRatio = bill.subtotal <= 0 ? 0.0 : bill.discount / bill.subtotal;
      for (final item in bill.items) {
        final product = itemProducts[item]!;
        await txn.insert('daily_sales', DailySale(id: _uuid.v4(), date: bill.date, billId: bill.id,
          productId: product.id, productName: product.name, costPrice: product.costPrice,
          salePrice: item.unitPrice * (1 - discountRatio), source: 'pos').toMap());
      }
    });

    await SyncQueueService.instance.queueOperation(operation: 'create', tableName: 'bills', documentId: bill.id, data: bill.toMap());
    for (var i = 0; i < bill.items.length; i++) {
      await SyncQueueService.instance.queueOperation(operation: 'create', tableName: 'bills/' + bill.id + '/items',
        documentId: itemCloudIds[i], data: {...bill.items[i].toMap(), 'cloudId': itemCloudIds[i], 'billId': bill.id});
    }
    for (final entry in newQuantities.entries) {
      final product = inventory.findById(entry.key);
      if (product == null) continue;
      final updated = Product(id: product.id, name: product.name, category: product.category, stockQuantity: entry.value,
        costPrice: product.costPrice, sellingPrice: product.sellingPrice, lowStockThreshold: product.lowStockThreshold);
      await SyncQueueService.instance.queueOperation(operation: 'update', tableName: 'products', documentId: updated.id, data: updated.toMap());
      inventory.applyStockAfterTransaction(updated.id, updated.stockQuantity);
    }
    savedBills.insert(0, bill); _billItemsCache[bill.id] = bill.items; clearCart(); return bill;
  }

  Future<void> loadHistory() async {
    final db = await DBService.instance.database;
    final billRows = await db.query('bills', orderBy: 'date DESC');
    savedBills.clear(); _billItemsCache.clear();
    for (final row in billRows) {
      final itemRows = await db.query('bill_items', where: 'billId = ?', whereArgs: [row['id']]);
      final items = itemRows.map((r) => BillItem.fromMap(r)).toList();
      final bill = Bill(id: row['id'] as String, date: DateTime.parse(row['date'] as String),
        customerName: row['customerName'] as String?, items: items,
        discount: (row['discount'] as num).toDouble(), taxPercent: (row['taxPercent'] as num).toDouble());
      savedBills.add(bill); _billItemsCache[bill.id] = items;
    }
    notifyListeners();
  }

  List<Bill> filterHistory({DateTime? date, String? customer, double? minAmount}) => savedBills.where((b) {
    final matchesDate = date == null || (b.date.year == date.year && b.date.month == date.month && b.date.day == date.day);
    final matchesCustomer = customer == null || customer.isEmpty || (b.customerName?.toLowerCase().contains(customer.toLowerCase()) ?? false);
    final matchesAmount = minAmount == null || b.grandTotal >= minAmount;
    return matchesDate && matchesCustomer && matchesAmount;
  }).toList();
}