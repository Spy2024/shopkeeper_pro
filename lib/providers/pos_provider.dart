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
  double get taxAmount => taxableSubtotal * (taxPercent / 100);
  double get taxableSubtotal => (subtotal - discount).clamp(0.0, double.infinity);
  double get grandTotal => taxableSubtotal + taxAmount;

  void addItem(String productName, int quantity, double unitPrice) {
    cart.add(BillItem(productName: productName, quantity: quantity, unitPrice: unitPrice));
    notifyListeners();
  }

  void removeItem(int index) {
    cart.removeAt(index);
    notifyListeners();
  }

  void setDiscount(double value) {
    discount = value;
    notifyListeners();
  }

  void setTax(double percent) {
    taxPercent = percent;
    notifyListeners();
  }

  void setCustomerName(String? name) {
    customerName = name;
    notifyListeners();
  }

  void clearCart() {
    cart.clear();
    discount = 0;
    taxPercent = 0;
    customerName = null;
    notifyListeners();
  }

  /// Persists the current cart as a completed bill, deducts stock, and
  /// resets the cart for the next customer. Returns the saved bill.
  Future<Bill> checkout(InventoryProvider inventory) async {
    if (cart.isEmpty) throw StateError('Cart is empty');
    if (discount < 0 || discount > subtotal) throw StateError('Invalid discount');
    if (taxPercent < 0 || taxPercent > 100) throw StateError('Invalid tax');

    final productsById = <String, Product>{};
    final quantitiesById = <String, int>{};
    for (final item in cart) {
      Product? product;
      if (item.productId != null) {
        product = inventory.findById(item.productId!);
      } else {
        final matches = inventory.products.where((p) => p.name == item.productName);
        product = matches.isEmpty ? null : matches.first;
      }
      if (product == null) throw StateError('Product not found');
      productsById[product.id] = product;
      quantitiesById[product.id] = (quantitiesById[product.id] ?? 0) + item.quantity;
    }
    for (final entry in quantitiesById.entries) {
      final product = productsById[entry.key]!;
      if (product.stockQuantity < entry.value) throw StateError('Insufficient stock');
    }

    final db = await DBService.instance.database;
    final bill = Bill(
      id: _uuid.v4(), date: DateTime.now(), customerName: customerName,
      items: List.unmodifiable(cart), discount: discount, taxPercent: taxPercent,
    );
    final newQuantities = <String, int>{};

    await db.transaction((txn) async {
      await txn.insert('bills', bill.toMap());
      for (final item in bill.items) {
        await txn.insert('bill_items', {
          ...item.toMap(),
          'billId': bill.id,
          'cloudId': _uuid.v4(),
        });
      }
      for (final entry in quantitiesById.entries) {
        final product = productsById[entry.key]!;
        final newQty = product.stockQuantity - entry.value;
        final changed = await txn.update('products', {'stockQuantity': newQty},
          where: 'id = ? AND stockQuantity >= ?', whereArgs: [product.id, entry.value]);
        if (changed != 1) throw StateError('Stock changed. Please retry checkout.');
        newQuantities[product.id] = newQty;
      }
      for (final item in bill.items) {
        final product = productsById[item.productId ?? ''] ??
            inventory.products.firstWhere((p) => p.name == item.productName);
        for (var i = 0; i < item.quantity; i++) {
          await txn.insert('daily_sales', DailySale(
            id: _uuid.v4(), date: bill.date, billId: bill.id, productId: product.id,
            productName: product.name, costPrice: product.costPrice,
            salePrice: item.unitPrice, source: 'pos',
          ).toMap());
        }
      }
    });

    await SyncQueueService.instance.queueOperation(
      operation: 'create', tableName: 'bills', documentId: bill.id, data: bill.toMap());
    for (final item in bill.items) {
      await SyncQueueService.instance.queueOperation(
        operation: 'create', tableName: 'bills/' + bill.id + '/items',
        documentId: item.productId ?? item.productName, data: item.toMap());
    }
    for (final entry in newQuantities.entries) {
      final product = inventory.findById(entry.key)!;
      final updated = Product(
        id: product.id, name: product.name, category: product.category,
        stockQuantity: entry.value, costPrice: product.costPrice,
        sellingPrice: product.sellingPrice, lowStockThreshold: product.lowStockThreshold,
      );
      await SyncQueueService.instance.queueOperation(
        operation: 'update', tableName: 'products', documentId: updated.id, data: updated.toMap());
      inventory.applyStockAfterTransaction(updated.id, updated.stockQuantity);
    }
    savedBills.insert(0, bill);
    _billItemsCache[bill.id] = bill.items;
    clearCart();
    return bill;
  }

  Future<void> loadHistory() async {
    final db = await DBService.instance.database;
    final billRows = await db.query('bills', orderBy: 'date DESC');
    savedBills.clear();
    _billItemsCache.clear();
    for (final row in billRows) {
      final itemRows = await db.query('bill_items', where: 'billId = ?', whereArgs: [row['id']]);
      final items = itemRows.map((r) => BillItem.fromMap(r)).toList();
      final bill = Bill(
        id: row['id'] as String,
        date: DateTime.parse(row['date'] as String),
        customerName: row['customerName'] as String?,
        items: items,
        discount: (row['discount'] as num).toDouble(),
        taxPercent: (row['taxPercent'] as num).toDouble(),
      );
      savedBills.add(bill);
      _billItemsCache[bill.id] = items;
    }
    notifyListeners();
  }

  List<Bill> filterHistory({DateTime? date, String? customer, double? minAmount}) {
    return savedBills.where((b) {
      final matchesDate = date == null ||
          (b.date.year == date.year && b.date.month == date.month && b.date.day == date.day);
      final matchesCustomer = customer == null ||
          customer.isEmpty ||
          (b.customerName?.toLowerCase().contains(customer.toLowerCase()) ?? false);
      final matchesAmount = minAmount == null || b.grandTotal >= minAmount;
      return matchesDate && matchesCustomer && matchesAmount;
    }).toList();
  }
}
