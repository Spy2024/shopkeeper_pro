import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/bill.dart';
import '../models/product.dart';
import '../models/daily_sale.dart';
import '../services/db_service.dart';
import '../services/business_operations_service.dart';
import 'inventory_provider.dart';

class PosProvider extends ChangeNotifier {
  final List<BillItem> cart = [];
  double discount = 0;
  double taxPercent = 0;
  String? customerName;
  final _uuid = const Uuid();
  final List<Bill> savedBills = [];
  final Map<String, List<BillItem>> _billItemsCache = {};
  bool isLoadingHistory = false;
  String? historyLoadError;

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

  Future<Bill> checkout(InventoryProvider inventory, {List<PaymentLine>? payments, String? branchId}) async {
    if (cart.isEmpty) throw StateError('Cart is empty');

    // Aggregate duplicate cart lines so a product cannot be oversold by
    // validating each line independently.
    final quantities = <String, int>{};
    for (final item in cart) {
      if (item.quantity <= 0 || item.unitPrice < 0) {
        throw StateError('Invalid quantity or price for ${item.productName}');
      }
      quantities.update(item.productName, (q) => q + item.quantity,
          ifAbsent: () => item.quantity);
    }

    final productByName = <String, Product>{};
    for (final name in quantities.keys) {
      final matches = inventory.products.where((p) => p.name == name);
      if (matches.isEmpty) throw StateError('Product not found: $name');
      productByName[name] = matches.first;
    }

    if (payments != null && payments.isNotEmpty) {
      if (payments.any((p) => p.amount <= 0 || p.method.trim().isEmpty)) {
        throw ArgumentError('Payment methods and amounts must be valid.');
      }
      final paid = payments.fold<double>(0, (sum, p) => sum + p.amount);
      if ((paid - grandTotal).abs() > 0.01) {
        throw StateError('Payments must equal the bill total.');
      }
    }

    final db = await DBService.instance.database;
    final bill = Bill(
      id: _uuid.v4(),
      date: DateTime.now(),
      customerName: customerName,
      branchId: branchId,
      items: List.of(cart),
      discount: discount,
      taxPercent: taxPercent,
    );

    await db.transaction((txn) async {
      // Re-check persisted stock and deduct it in the same transaction as
      // bill, bill items, and daily sales to avoid partial checkouts.
      for (final entry in quantities.entries) {
        final product = productByName[entry.key]!;
        if (branchId != null) {
          final branchRows = await txn.query('branch_stock',
              columns: ['id', 'quantity'],
              where: 'branchId = ? AND productId = ?',
              whereArgs: [branchId, product.id],
              limit: 1);
          if (branchRows.isEmpty) {
            throw StateError('No stock allocated to this branch for ${entry.key}.');
          }
          final stock = (branchRows.first['quantity'] as num).toInt();
          if (stock < entry.value) {
            throw StateError('Insufficient branch stock for ${entry.key}: available $stock, requested ${entry.value}');
          }
          await txn.update('branch_stock', {'quantity': stock - entry.value},
              where: 'id = ?', whereArgs: [branchRows.first['id']]);
        } else {
          final rows = await txn.query('products',
              columns: ['stockQuantity'],
              where: 'id = ?',
              whereArgs: [product.id],
              limit: 1);
          if (rows.isEmpty) throw StateError('Product no longer exists: ${entry.key}');
          final stock = (rows.first['stockQuantity'] as num).toInt();
          if (stock < entry.value) {
            throw StateError('Insufficient stock for ${entry.key}: available $stock, requested ${entry.value}');
          }
          await txn.update('products', {'stockQuantity': stock - entry.value},
              where: 'id = ?', whereArgs: [product.id]);
        }
      }

      await txn.insert('bills', bill.toMap());
      if (payments != null) {
        for (final payment in payments) {
          await txn.insert('payments', {
            'id': _uuid.v4(),
            'billId': bill.id,
            'method': payment.method.trim(),
            'amount': payment.amount,
            'reference': payment.reference,
          });
        }
      }
      for (final item in bill.items) {
        await txn.insert('bill_items', {...item.toMap(), 'billId': bill.id});
        final product = productByName[item.productName]!;
        await txn.insert('daily_sales', DailySale(
          id: _uuid.v4(),
          date: bill.date,
          productName: item.productName,
          costPrice: product.costPrice,
          salePrice: item.unitPrice,
        ).toMap());
      }

      final saved = await txn.query('bills',
          where: 'id = ?', whereArgs: [bill.id], limit: 1);
      final savedItems = await txn.query('bill_items',
          where: 'billId = ?', whereArgs: [bill.id]);
      if (saved.length != 1 || savedItems.length != bill.items.length) {
        throw StateError('Checkout persistence verification failed.');
      }
    });

    savedBills.removeWhere((existing) => existing.id == bill.id);
    savedBills.insert(0, bill);
    _billItemsCache[bill.id] = bill.items;
    clearCart();
    if (branchId == null) await inventory.load();
    return bill;
  }

  Future<void> loadHistory() async {
    isLoadingHistory = true;
    historyLoadError = null;
    notifyListeners();
    try {
      final db = await DBService.instance.database;
      final billRows = await db.query('bills', orderBy: 'date DESC');
      final loadedBills = <Bill>[];
      final loadedItems = <String, List<BillItem>>{};
      for (final row in billRows) {
        final billId = row['id'] as String;
        final itemRows = await db.query('bill_items',
            where: 'billId = ?', whereArgs: [billId]);
        final items = itemRows
            .map((r) => BillItem.fromMap(Map<String, dynamic>.from(r)))
            .toList();
        loadedBills.add(Bill(
          id: billId,
          date: DateTime.parse(row['date'] as String),
          customerName: row['customerName'] as String?,
          branchId: row['branchId'] as String?,
          items: items,
          discount: (row['discount'] as num?)?.toDouble() ?? 0,
          taxPercent: (row['taxPercent'] as num?)?.toDouble() ?? 0,
        ));
        loadedItems[billId] = items;
      }
      savedBills
        ..clear()
        ..addAll(loadedBills);
      _billItemsCache
        ..clear()
        ..addAll(loadedItems);
    } catch (error, stackTrace) {
      historyLoadError = 'Bill history load nahi ho saki: $error';
      debugPrint('[PosProvider] loadHistory failed: $error\n$stackTrace');
    } finally {
      isLoadingHistory = false;
      notifyListeners();
    }
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