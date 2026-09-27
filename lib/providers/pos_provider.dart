import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/bill.dart';
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
    final db = await DBService.instance.database;
    final bill = Bill(
      id: _uuid.v4(),
      date: DateTime.now(),
      customerName: customerName,
      items: List.of(cart),
      discount: discount,
      taxPercent: taxPercent,
    );

    await db.insert('bills', bill.toMap());
    for (final item in bill.items) {
      await db.insert('bill_items', {...item.toMap(), 'billId': bill.id});
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
