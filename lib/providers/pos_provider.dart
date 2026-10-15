import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/bill.dart';
import '../models/daily_sale.dart';
import '../models/product.dart';
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
  double get effectiveDiscount => discount.clamp(0, subtotal).toDouble();
  double get taxAmount => (subtotal - effectiveDiscount) * (taxPercent / 100);
  double get grandTotal => (subtotal - effectiveDiscount) + taxAmount;

  void addItem(String productName, int quantity, double unitPrice) {
    if (productName.trim().isEmpty || quantity <= 0 || unitPrice < 0) return;
    cart.add(BillItem(productName: productName.trim(), quantity: quantity, unitPrice: unitPrice));
    notifyListeners();
  }

  void removeItem(int index) {
    if (index < 0 || index >= cart.length) return;
    cart.removeAt(index);
    notifyListeners();
  }

  void setDiscount(double value) {
    discount = value < 0 ? 0 : value;
    notifyListeners();
  }

  void setTax(double percent) {
    taxPercent = percent < 0 ? 0 : percent;
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

  Future<Bill> checkout(InventoryProvider inventory) async {
    if (cart.isEmpty) throw StateError('Cart is empty');

    final productsByName = <String, Product>{
      for (final product in inventory.products) product.name: product,
    };

    for (final item in cart) {
      final product = productsByName[item.productName];
      if (product == null) {
        throw StateError('Product not found: ${item.productName}');
      }
      if (product.stockQuantity < item.quantity) {
        throw StateError('Insufficient stock for ${item.productName}');
      }
    }

    final db = await DBService.instance.database;
    final bill = Bill(
      id: _uuid.v4(),
      date: DateTime.now(),
      customerName: customerName,
      items: List<BillItem>.unmodifiable(cart),
      discount: discount,
      taxPercent: taxPercent,
    );

    final updatedProducts = <String, Product>{};
    final createdSales = <DailySale>[];

    await db.transaction((txn) async {
      await txn.insert('bills', bill.toMap());

      for (final item in bill.items) {
        await txn.insert('bill_items', {...item.toMap(), 'billId': bill.id});

        final product = productsByName[item.productName]!;
        final currentRows = await txn.query(
          'products',
          where: 'id = ?',
          whereArgs: [product.id],
          limit: 1,
        );
        if (currentRows.isEmpty) {
          throw StateError('Product disappeared during checkout: ${item.productName}');
        }

        final current = currentRows.first;
        final currentStock = (current['stockQuantity'] as num).toInt();
        final newStock = currentStock - item.quantity;
        if (newStock < 0) {
          throw StateError('Insufficient stock for ${item.productName}');
        }

        final changed = await txn.update(
          'products',
          {'stockQuantity': newStock},
          where: 'id = ? AND stockQuantity >= ?',
          whereArgs: [product.id, item.quantity],
        );
        if (changed != 1) {
          throw StateError('Stock update failed for ${item.productName}');
        }

        final updatedRows = await txn.query(
          'products',
          where: 'id = ?',
          whereArgs: [product.id],
          limit: 1,
        );
        if (updatedRows.isEmpty ||
            (updatedRows.first['stockQuantity'] as num).toInt() != newStock) {
          throw StateError('Stock verification failed for ${item.productName}');
        }

        updatedProducts[product.id] =
            Product.fromMap(Map<String, dynamic>.from(updatedRows.first));

        for (var i = 0; i < item.quantity; i++) {
          final sale = DailySale(
            id: _uuid.v4(),
            date: bill.date,
            productName: item.productName,
            costPrice: product.costPrice,
            salePrice: item.unitPrice,
          );
          await txn.insert('daily_sales', sale.toMap());
          createdSales.add(sale);
        }
      }
    });

    try {
      await SyncQueueService.instance.queueOperation(
        operation: 'create',
        tableName: 'bills',
        documentId: bill.id,
        data: bill.toSyncMap(),
      );
      for (final product in updatedProducts.values) {
        await SyncQueueService.instance.queueOperation(
          operation: 'update',
          tableName: 'products',
          documentId: product.id,
          data: product.toMap(),
        );
      }
      for (final sale in createdSales) {
        await SyncQueueService.instance.queueOperation(
          operation: 'create',
          tableName: 'daily_sales',
          documentId: sale.id,
          data: sale.toMap(),
        );
      }
    } catch (e) {
      debugPrint('[POS] Queue write deferred; full sync will reconcile: $e');
    }

    await inventory.load();
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
      final items = itemRows
          .map((r) => BillItem.fromMap(Map<String, dynamic>.from(r)))
          .toList();
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
