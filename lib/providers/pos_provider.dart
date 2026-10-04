import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/bill.dart';
import '../models/product.dart';
import '../models/daily_sale.dart';
import '../services/db_service.dart';
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
  double get taxAmount => (subtotal - discount) * (taxPercent / 100);
  double get grandTotal => (subtotal - discount) + taxAmount;

  void addItem(String productName, int quantity, double unitPrice) {
    if (quantity <= 0 || unitPrice < 0) return;
    cart.add(BillItem(productName: productName, quantity: quantity, unitPrice: unitPrice));
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

    for (final item in cart) {
      final matches = inventory.products.where((p) => p.name == item.productName);
      if (matches.isEmpty) throw StateError('Product not found: ${item.productName}');
      final product = matches.first;
      if (product.stockQuantity < item.quantity) {
        throw StateError('Insufficient stock for ${item.productName}');
      }
    }

    final db = await DBService.instance.database;
    final bill = Bill(
      id: _uuid.v4(),
      date: DateTime.now(),
      customerName: customerName,
      items: List.of(cart),
      discount: discount,
      taxPercent: taxPercent,
    );

    await db.transaction((txn) async {
      await txn.insert('bills', bill.toMap());
      for (final item in bill.items) {
        await txn.insert('bill_items', {...item.toMap(), 'billId': bill.id});
        final product = inventory.products.firstWhere((p) => p.name == item.productName);
        for (int i = 0; i < item.quantity; i++) {
          await txn.insert('daily_sales', DailySale(
            id: _uuid.v4(),
            date: bill.date,
            productName: item.productName,
            costPrice: product.costPrice,
            salePrice: item.unitPrice,
          ).toMap());
        }
      }
    });

    for (final item in bill.items) {
      await inventory.deductStock(item.productName, item.quantity);
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
      final matchesDate = date == null || (b.date.year == date.year && b.date.month == date.month && b.date.day == date.day);
      final matchesCustomer = customer == null || customer.isEmpty || (b.customerName?.toLowerCase().contains(customer.toLowerCase()) ?? false);
      final matchesAmount = minAmount == null || b.grandTotal >= minAmount;
      return matchesDate && matchesCustomer && matchesAmount;
    }).toList();
  }
}