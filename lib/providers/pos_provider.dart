import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/bill.dart';
import '../models/product.dart';
import '../models/daily_sale.dart';
import '../services/db_service.dart';
import '../services/sync_queue_service.dart';
import 'inventory_provider.dart';

/// Resolves bill items to inventory records without silently switching product
/// identity. Name-based lookup is retained only for legacy items without an ID.
Product? resolveProductForBillItem(BillItem item, List<Product> products) {
  final productId = item.productId;
  if (productId != null) {
    for (final product in products) {
      if (product.id == productId) return product;
    }
    return null;
  }

  // Older/manual cart entries sometimes stored the product ID in the name field.
  final legacyValue = item.productName.trim();
  for (final product in products) {
    if (product.id == legacyValue) return product;
  }

  final normalizedName = legacyValue.toLowerCase();
  for (final product in products) {
    if (product.name.trim().toLowerCase() == normalizedName) return product;
  }
  return null;
}

/// Refuses to sell products that are past their expiry date.
/// The check is intentionally shared by checkout and unit tests.
void validateProductCanBeSold(Product product) {
  if (product.isExpired) {
    throw StateError('Cannot sell expired product: ${product.name}');
  }
}

/// Sums only the sold quantity for the selected product and unit-price line.
/// This prevents a more expensive line for the same product from being
/// refunded repeatedly using quantities sold at a lower price.
int soldQuantityForReturnLine({
  required Bill bill,
  required BillItem item,
  required Product product,
}) {
  return bill.items.where((candidate) {
    final sameProduct = candidate.productId != null
        ? candidate.productId == product.id
        : candidate.productName.trim().toLowerCase() ==
            product.name.trim().toLowerCase();
    return sameProduct && candidate.unitPrice == item.unitPrice;
  }).fold<int>(0, (sum, candidate) => sum + candidate.quantity);
}

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
    if (cleanName.isEmpty ||
        quantity <= 0 ||
        !unitPrice.isFinite ||
        unitPrice <= 0 ||
        !(quantity * unitPrice).isFinite) {
      throw ArgumentError('Cart item must have a name, positive quantity, and finite positive price and total.');
    }
    // Only merge identical product/price lines. If a cashier changes a price
    // mid-cart, preserve the earlier line price for correct totals and refunds.
    final existingIndex = productId == null
        ? -1
        : cart.indexWhere((item) =>
            item.productId == productId && item.unitPrice == unitPrice);
    if (existingIndex >= 0) {
      final existing = cart[existingIndex];
      cart[existingIndex] = BillItem(
        productId: existing.productId,
        productName: existing.productName,
        quantity: existing.quantity + quantity,
        unitPrice: existing.unitPrice,
      );
    } else {
      cart.add(BillItem(
        productId: productId,
        productName: cleanName,
        quantity: quantity,
        unitPrice: unitPrice,
      ));
    }
    notifyListeners();
  }

  void removeItem(int index) {
    if (index < 0 || index >= cart.length) return;
    cart.removeAt(index);
    notifyListeners();
  }

  void setDiscount(double value) {
    if (!value.isFinite || value < 0) {
      throw ArgumentError('Discount must be a finite, non-negative amount.');
    }
    discount = value > subtotal ? subtotal : value;
    notifyListeners();
  }

  void setTax(double percent) {
    if (!percent.isFinite || percent < 0 || percent > 100) {
      throw ArgumentError('Tax must be a finite percentage between 0 and 100.');
    }
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
    if (!subtotal.isFinite || !grandTotal.isFinite) {
      throw StateError('Cart total is outside the supported amount range.');
    }
    if (!discount.isFinite || discount < 0 || discount > subtotal) {
      throw StateError('Invalid discount');
    }
    if (!taxPercent.isFinite || taxPercent < 0 || taxPercent > 100) {
      throw StateError('Invalid tax');
    }

    final productsById = <String, Product>{};
    final quantitiesById = <String, int>{};
    final itemProducts = <BillItem, Product>{};
    for (final item in cart) {
      final product = resolveProductForBillItem(item, inventory.products);
      if (product == null) throw StateError('Product not found: ${item.productName}');
      validateProductCanBeSold(product);
      if (item.quantity <= 0 || item.unitPrice <= 0) throw StateError('Invalid quantity or price');
      productsById[product.id] = product;
      quantitiesById[product.id] = (quantitiesById[product.id] ?? 0) + item.quantity;
      itemProducts[item] = product;
    }
    for (final entry in quantitiesById.entries) {
      final product = productsById[entry.key]!;
      if (product.stockQuantity < entry.value) throw StateError('Insufficient stock for ${product.name}');
    }

    // Store resolved inventory IDs and canonical names, including legacy cart entries.
    final normalizedItems = cart.map((item) {
      final product = itemProducts[item]!;
      return BillItem(productId: product.id, productName: product.name,
        quantity: item.quantity, unitPrice: item.unitPrice);
    }).toList(growable: false);

    final db = await DBService.instance.database;
    final bill = Bill(id: _uuid.v4(), date: DateTime.now(), customerName: customerName,
      items: List.unmodifiable(normalizedItems), discount: discount, taxPercent: taxPercent);
    final newQuantities = <String, int>{};
    final itemCloudIds = List<String>.generate(bill.items.length, (_) => _uuid.v4());

    await db.transaction((txn) async {
      await txn.insert('bills', bill.toMap());
      for (var i = 0; i < bill.items.length; i++) {
        await txn.insert('bill_items', {...bill.items[i].toMap(), 'billId': bill.id, 'cloudId': itemCloudIds[i]});
      }
      for (final entry in quantitiesById.entries) {
        final product = productsById[entry.key]!;
        // Decrement the database's current value atomically. Calculating from
        // the provider cache could overwrite a concurrent stock receipt/edit.
        final changed = await txn.rawUpdate(
          'UPDATE products SET stockQuantity = stockQuantity - ? '
          'WHERE id = ? AND stockQuantity >= ?',
          [entry.value, product.id, entry.value],
        );
        if (changed != 1) {
          throw StateError('Stock changed or is insufficient for ${product.name}. Please retry checkout.');
        }
        final stockRows = await txn.query(
          'products',
          columns: ['stockQuantity'],
          where: 'id = ?',
          whereArgs: [product.id],
          limit: 1,
        );
        if (stockRows.isEmpty) throw StateError('Product not found after stock update.');
        newQuantities[product.id] = (stockRows.single['stockQuantity'] as num).toInt();
      }
      final discountRatio = bill.subtotal <= 0 ? 0.0 : bill.discount / bill.subtotal;
      for (final item in bill.items) {
        final product = productsById[item.productId]!;
        await txn.insert('daily_sales', DailySale(id: _uuid.v4(), date: bill.date, billId: bill.id,
          productId: product.id, productName: product.name, costPrice: product.costPrice,
          salePrice: item.unitPrice * (1 - discountRatio), quantity: item.quantity, source: 'pos').toMap());
      }
    });

    // The SQLite transaction is the source of truth. A cloud-queue failure must
    // never report a committed checkout as failed; the next full sync can reconcile it.
    for (final entry in newQuantities.entries) {
      final product = productsById[entry.key]!;
      final updated = Product(
        id: product.id,
        name: product.name,
        category: product.category,
        stockQuantity: entry.value,
        costPrice: product.costPrice,
        sellingPrice: product.sellingPrice,
        lowStockThreshold: product.lowStockThreshold,
        barcode: product.barcode,
        expiryDate: product.expiryDate,
      );
      inventory.applyStockAfterTransaction(updated.id, updated.stockQuantity);
    }
    await _queueSafely(
      operation: 'create', tableName: 'bills', documentId: bill.id, data: bill.toMap());
    for (var i = 0; i < bill.items.length; i++) {
      await _queueSafely(
        operation: 'create',
        tableName: 'bills/${bill.id}/items',
        documentId: itemCloudIds[i],
        data: {...bill.items[i].toMap(), 'cloudId': itemCloudIds[i], 'billId': bill.id},
      );
    }
    for (final entry in newQuantities.entries) {
      final product = productsById[entry.key]!;
      final updated = Product(
        id: product.id,
        name: product.name,
        category: product.category,
        stockQuantity: entry.value,
        costPrice: product.costPrice,
        sellingPrice: product.sellingPrice,
        lowStockThreshold: product.lowStockThreshold,
        barcode: product.barcode,
        expiryDate: product.expiryDate,
      );
      await _queueSafely(
        operation: 'update', tableName: 'products', documentId: updated.id, data: updated.toMap());
    }
    savedBills.insert(0, bill); _billItemsCache[bill.id] = bill.items; clearCart(); return bill;
  }


  Future<double> returnItem({
    required Bill bill,
    required BillItem item,
    required int quantity,
    required String reason,
    required InventoryProvider inventory,
  }) async {
    if (quantity <= 0) throw ArgumentError('Return quantity must be positive.');
    if (reason.trim().isEmpty) throw ArgumentError('A return reason is required.');

    final product = resolveProductForBillItem(item, inventory.products);
    if (product == null) {
      throw StateError('The returned product is no longer in inventory: ${item.productName}');
    }

    final resolvedProduct = product;
    final soldQuantity = soldQuantityForReturnLine(
      bill: bill,
      item: item,
      product: resolvedProduct,
    );
    final db = await DBService.instance.database;
    final refundAmount = bill.refundFor(item, quantity);
    final returnId = _uuid.v4();
    final returnedAt = DateTime.now();
    final discountRatio = bill.subtotal <= 0 ? 0.0 : bill.discount / bill.subtotal;
    final returnSale = DailySale(
      id: _uuid.v4(),
      date: returnedAt,
      billId: bill.id,
      productId: resolvedProduct.id,
      productName: resolvedProduct.name,
      costPrice: -resolvedProduct.costPrice,
      salePrice: -item.unitPrice * (1 - discountRatio),
      quantity: quantity,
      source: 'return',
    );
    final returnRow = <String, dynamic>{
      'id': returnId,
      'billId': bill.id,
      'productId': resolvedProduct.id,
      'productName': resolvedProduct.name,
      'unitPrice': item.unitPrice,
      'quantity': quantity,
      'refundAmount': refundAmount,
      'date': returnedAt.toIso8601String(),
      'reason': reason.trim(),
    };
    late int newStock;
    await db.transaction((txn) async {
      final priorRows = await txn.rawQuery(
        'SELECT COALESCE(SUM(quantity), 0) AS returnedQuantity FROM bill_returns WHERE billId = ? AND productId = ? AND (unitPrice = ? OR unitPrice = 0)',
        [bill.id, resolvedProduct.id, item.unitPrice],
      );
      final alreadyReturned = (priorRows.first['returnedQuantity'] as num).toInt();
      if (quantity + alreadyReturned > soldQuantity) {
        throw StateError('Only ${soldQuantity - alreadyReturned} unit(s) remain eligible for return.');
      }
      final stockRows = await txn.query(
        'products',
        columns: ['stockQuantity'],
        where: 'id = ?',
        whereArgs: [resolvedProduct.id],
        limit: 1,
      );
      if (stockRows.isEmpty) throw StateError('Product not found in local database.');
      newStock = (stockRows.first['stockQuantity'] as num).toInt() + quantity;
      await txn.update('products', {'stockQuantity': newStock},
          where: 'id = ?', whereArgs: [resolvedProduct.id]);
      await txn.insert('bill_returns', returnRow);
      await txn.insert('daily_sales', returnSale.toMap());
    });

    inventory.applyStockAfterTransaction(resolvedProduct.id, newStock);
    await _queueSafely(
      operation: 'create', tableName: 'returns', documentId: returnId, data: returnRow);
    await _queueSafely(
      operation: 'create', tableName: 'sales', documentId: returnSale.id, data: returnSale.toMap());
    await _queueSafely(
      operation: 'update',
      tableName: 'products',
      documentId: resolvedProduct.id,
      data: Product(
        id: resolvedProduct.id,
        name: resolvedProduct.name,
        category: resolvedProduct.category,
        stockQuantity: newStock,
        costPrice: resolvedProduct.costPrice,
        sellingPrice: resolvedProduct.sellingPrice,
        lowStockThreshold: resolvedProduct.lowStockThreshold,
        barcode: resolvedProduct.barcode,
        expiryDate: resolvedProduct.expiryDate,
      ).toMap(),
    );
    return refundAmount;
  }

  Future<void> _queueSafely({
    required String operation,
    required String tableName,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    try {
      await SyncQueueService.instance.queueOperation(
        operation: operation,
        tableName: tableName,
        documentId: documentId,
        data: data,
      );
    } catch (e) {
      // Do not let one failed queue insert prevent later records from being
      // queued. Local checkout/return data remains committed in SQLite.
      debugPrint('[PosProvider] Could not queue $tableName/$documentId; next full sync should reconcile it: $e');
    }
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