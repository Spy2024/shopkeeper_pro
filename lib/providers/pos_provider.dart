import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/bill.dart';
import '../models/product.dart';
import '../models/daily_sale.dart';
import '../services/db_service.dart';
import '../services/sync_queue_service.dart';
import '../services/branch_accounting_service.dart';
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

/// Resolves inventory identity for returns. New/manual bill-only lines have
/// no productId and must never restore stock just because their name happens to
/// match a catalogue product. Legacy name resolution remains available through
/// resolveProductForBillItem for other compatibility paths.
Product? resolveProductForReturn(BillItem item, List<Product> products) {
  if (item.productId == null) return null;
  return resolveProductForBillItem(item, products);
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

/// Rehydrates a persisted bill without losing branch attribution.
Bill billFromDatabaseRow(Map<String, Object?> row, List<BillItem> items) {
  return Bill(
    id: row['id'] as String,
    date: DateTime.parse(row['date'] as String),
    customerName: row['customerName'] as String?,
    customerId: row['customerId'] as String?,
    customerAddress: row['customerAddress'] as String?,
    customerPhone: row['customerPhone'] as String?,
    customerEmail: row['customerEmail'] as String?,
    branchId: row['branchId'] as String?,
    items: items,
    discount: (row['discount'] as num).toDouble(),
    taxPercent: (row['taxPercent'] as num).toDouble(),
  );
}

/// Creates a stable, bill-scoped key for returns of manual bill-only lines.
/// It satisfies the legacy returns table's non-null productId column without
/// pretending that a manual line is an inventory product.
String manualBillItemReturnKey(Bill bill, BillItem item) =>
    'manual:${bill.id}:${item.productName.trim().toLowerCase()}:${item.unitPrice.toStringAsFixed(4)}';

class PosProvider extends ChangeNotifier {
  final List<BillItem> cart = [];
  double discount = 0;
  double taxPercent = 0;
  String? customerName;
  String? customerAddress;
  String? customerPhone;
  String? customerEmail;
  final _uuid = const Uuid();
  final List<Bill> savedBills = [];
  final Map<String, List<BillItem>> _billItemsCache = {};
  bool isLoadingHistory = false;
  String? historyLoadError;

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

  void setCustomerDetails({String? name, String? address, String? phone, String? email}) {
    customerName = name?.trim().isEmpty == true ? null : name?.trim();
    customerAddress = address?.trim().isEmpty == true ? null : address?.trim();
    customerPhone = phone?.trim().isEmpty == true ? null : phone?.trim();
    customerEmail = email?.trim().isEmpty == true ? null : email?.trim();
    notifyListeners();
  }

  void clearCart() {
    cart.clear(); discount = 0; taxPercent = 0; customerName = null;
    customerAddress = null; customerPhone = null; customerEmail = null; notifyListeners();
  }

  Future<Bill> checkout(InventoryProvider inventory, {String? branchId, String? customerId, List<PaymentAllocationInput> paymentAllocations = const []}) async {
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

    final normalizedAllocations = paymentAllocations.isEmpty
        ? <PaymentAllocationInput>[PaymentAllocationInput(method: 'cash', amount: grandTotal)]
        : List<PaymentAllocationInput>.unmodifiable(paymentAllocations);
    const paymentMethods = {'cash', 'card', 'bank', 'wallet', 'credit', 'other'};
    for (final allocation in normalizedAllocations) {
      if (!paymentMethods.contains(allocation.method) ||
          !allocation.amount.isFinite || allocation.amount < 0) {
        throw ArgumentError('Payment allocations must use a supported method and non-negative finite amounts.');
      }
    }
    final allocatedTotal = normalizedAllocations.fold<double>(0, (sum, item) => sum + item.amount);
    if ((allocatedTotal - grandTotal).abs() > 0.005) {
      throw StateError('Payment allocations must equal the bill total.');
    }
    final creditDue = normalizedAllocations
        .where((item) => item.method == 'credit')
        .fold<double>(0, (sum, item) => sum + item.amount);
    if (creditDue > 0 && (customerId == null || customerId.trim().isEmpty)) {
      throw StateError('Select a customer before recording a credit/udhaar payment.');
    }

    final normalizedBranchId = branchId?.trim();
    if (normalizedBranchId != null && normalizedBranchId.isEmpty) {
      throw ArgumentError('Branch ID cannot be empty.');
    }
    if (normalizedBranchId != null) {
      final branchRows = await (await DBService.instance.database).query(
        'branches',
        columns: ['id', 'isActive'],
        where: 'id = ?',
        whereArgs: [normalizedBranchId],
        limit: 1,
      );
      if (branchRows.isEmpty || (branchRows.single['isActive'] as num?)?.toInt() != 1) {
        throw StateError('Selected branch does not exist or is inactive.');
      }
    }

    final productsById = <String, Product>{};
    final quantitiesById = <String, int>{};
    final itemProducts = <BillItem, Product>{};
    for (final item in cart) {
      if (item.quantity <= 0 || !item.unitPrice.isFinite || item.unitPrice <= 0) {
        throw StateError('Invalid quantity or price');
      }

      // Manually entered bill lines have no productId. They are bill-only
      // items and must not require a catalogue record or change stock.
      if (item.productId == null) continue;

      final product = resolveProductForBillItem(item, inventory.products);
      if (product == null) throw StateError('Product not found: ${item.productName}');
      validateProductCanBeSold(product);
      productsById[product.id] = product;
      quantitiesById[product.id] = (quantitiesById[product.id] ?? 0) + item.quantity;
      itemProducts[item] = product;
    }
    for (final entry in quantitiesById.entries) {
      final product = productsById[entry.key]!;
      if (product.stockQuantity < entry.value) throw StateError('Insufficient stock for ${product.name}');
    }

    // Catalogue-linked lines use canonical product identity. Manual lines
    // remain in the bill with a null productId and no stock deduction.
    final normalizedItems = cart.map((item) {
      final product = itemProducts[item];
      return BillItem(
        productId: product?.id,
        productName: product?.name ?? item.productName.trim(),
        quantity: item.quantity,
        unitPrice: item.unitPrice,
      );
    }).toList(growable: false);

    final db = await DBService.instance.database;
    final bill = Bill(id: _uuid.v4(), date: DateTime.now(), customerName: customerName, customerId: customerId?.trim(), customerAddress: customerAddress, customerPhone: customerPhone, customerEmail: customerEmail, branchId: normalizedBranchId,
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
        if (normalizedBranchId != null) {
          final branchChanged = await txn.rawUpdate(
            'UPDATE branch_stock SET quantity = quantity - ?, updatedAt = ? '
            'WHERE branchId = ? AND productId = ? AND quantity >= ?',
            [entry.value, bill.date.toIso8601String(), normalizedBranchId, product.id, entry.value],
          );
          if (branchChanged != 1) {
            throw StateError('Insufficient stock in selected branch for ${product.name}.');
          }
        }
        // Decrement the database's current value atomically. Calculating from
        // the provider cache could overwrite a concurrent stock receipt/edit. Calculating from
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
      final now = bill.date.toIso8601String();
      for (final allocation in normalizedAllocations) {
        await txn.insert('payment_allocations', {
          'id': _uuid.v4(),
          'billId': bill.id,
          'method': allocation.method,
          'amount': allocation.amount,
          'reference': allocation.reference?.trim(),
          'createdAt': now,
        });
      }
      final cashPaid = normalizedAllocations
          .where((item) => item.method == 'cash')
          .fold<double>(0, (sum, item) => sum + item.amount);
      if (normalizedBranchId != null && cashPaid > 0) {
        await txn.insert('branch_cash_transactions', {
          'id': _uuid.v4(),
          'branchId': normalizedBranchId,
          'type': 'sale',
          'amount': cashPaid,
          'date': now,
          'referenceId': bill.id,
          'note': 'POS cash payment',
        });
      }
      if (creditDue > 0) {
        await txn.insert('customer_ledger', {
          'id': _uuid.v4(),
          'customerId': customerId!.trim(),
          'type': 'sale_due',
          'amount': creditDue,
          'date': now,
          'referenceId': bill.id,
          'note': 'Udhaar for bill ${bill.id}',
        });
      }
      final discountRatio = bill.subtotal <= 0 ? 0.0 : bill.discount / bill.subtotal;
      for (final item in bill.items) {
        final product = item.productId == null ? null : productsById[item.productId];
        await txn.insert('daily_sales', DailySale(
          id: _uuid.v4(),
          date: bill.date,
          billId: bill.id,
          productId: product?.id,
          productName: product?.name ?? item.productName,
          // Manual bill-only lines have no inventory cost record.
          costPrice: product?.costPrice ?? 0,
          salePrice: item.unitPrice * (1 - discountRatio),
          quantity: item.quantity,
          source: 'pos',
          branchId: normalizedBranchId,
        ).toMap());
      }
    });

    // Verify the committed bill and every line can be read back before the
    // checkout is reported as successful or a PDF is generated.
    final persistedBillRows = await db.query(
      'bills', where: 'id = ?', whereArgs: [bill.id], limit: 1,
    );
    final persistedItemRows = await db.query(
      'bill_items', where: 'billId = ?', whereArgs: [bill.id],
    );
    if (persistedBillRows.length != 1 || persistedItemRows.length != bill.items.length) {
      throw StateError('Checkout could not verify the saved bill. Please do not retry blindly; check Bill History first.');
    }

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
    String refundMethod = 'cash',
  }) async {
    if (quantity <= 0) throw ArgumentError('Return quantity must be positive.');
    if (reason.trim().isEmpty) throw ArgumentError('A return reason is required.');
    const supportedRefundMethods = {'cash', 'card', 'bank', 'wallet', 'credit', 'other'};
    if (!supportedRefundMethods.contains(refundMethod)) {
      throw ArgumentError.value(refundMethod, 'refundMethod', 'Unsupported refund method.');
    }
    if (refundMethod == 'credit' && (bill.customerId == null || bill.customerId!.trim().isEmpty)) {
      throw StateError('Select a customer on the original bill before issuing a credit refund.');
    }

    final resolvedProduct = resolveProductForReturn(item, inventory.products);
    if (resolvedProduct == null && item.productId != null) {
      throw StateError('The returned product is no longer in inventory: ${item.productName}');
    }
    // A bill-only line has no product ID and must never change stock. If a
    // legacy ID-less line still matches a catalogue product, preserve its stock
    // restoration behaviour.
    final isManualLine = resolvedProduct == null;
    final returnProductId = resolvedProduct?.id ?? manualBillItemReturnKey(bill, item);
    final returnProductName = resolvedProduct?.name ?? item.productName;
    final soldQuantity = isManualLine
        ? bill.items.where((candidate) =>
            candidate.productId == null &&
            candidate.productName.trim().toLowerCase() == item.productName.trim().toLowerCase() &&
            candidate.unitPrice == item.unitPrice)
            .fold<int>(0, (sum, candidate) => sum + candidate.quantity)
        : soldQuantityForReturnLine(bill: bill, item: item, product: resolvedProduct);
    final db = await DBService.instance.database;
    final refundAmount = bill.refundFor(item, quantity);
    final returnId = _uuid.v4();
    final returnedAt = DateTime.now();
    final discountRatio = bill.subtotal <= 0 ? 0.0 : bill.discount / bill.subtotal;
    final returnSale = DailySale(
      id: _uuid.v4(),
      date: returnedAt,
      billId: bill.id,
      productId: resolvedProduct?.id,
      productName: returnProductName,
      costPrice: -(resolvedProduct?.costPrice ?? 0),
      salePrice: -item.unitPrice * (1 - discountRatio),
      quantity: quantity,
      source: 'return',
      branchId: bill.branchId,
    );
    final returnRow = <String, dynamic>{
      'id': returnId,
      'billId': bill.id,
      'productId': returnProductId,
      'productName': returnProductName,
      'unitPrice': item.unitPrice,
      'quantity': quantity,
      'refundAmount': refundAmount,
      'refundMethod': refundMethod,
      'date': returnedAt.toIso8601String(),
      'reason': reason.trim(),
      'branchId': bill.branchId,
    };
    final cashRefundRow = refundMethod == 'cash' && bill.branchId != null
        ? <String, dynamic>{
            'id': _uuid.v4(),
            'branchId': bill.branchId,
            'type': 'refund',
            'amount': refundAmount,
            'date': returnedAt.toIso8601String(),
            'referenceId': returnId,
            'note': 'Cash refund for bill ${bill.id}',
          }
        : null;
    final customerRefundRow = refundMethod == 'credit'
        ? <String, dynamic>{
            'id': _uuid.v4(),
            'customerId': bill.customerId,
            'type': 'refund',
            'amount': refundAmount,
            'date': returnedAt.toIso8601String(),
            'referenceId': returnId,
            'note': 'Credit refund for bill ${bill.id}',
          }
        : null;
    int? newStock;
    await db.transaction((txn) async {
      final priorRows = await txn.rawQuery(
        'SELECT COALESCE(SUM(quantity), 0) AS returnedQuantity FROM bill_returns WHERE billId = ? AND productId = ? AND (unitPrice = ? OR unitPrice = 0)',
        [bill.id, returnProductId, item.unitPrice],
      );
      final alreadyReturned = (priorRows.first['returnedQuantity'] as num).toInt();
      if (quantity + alreadyReturned > soldQuantity) {
        throw StateError('Only ${soldQuantity - alreadyReturned} unit(s) remain eligible for return.');
      }
      if (resolvedProduct != null) {
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
      }
      if (bill.branchId != null && resolvedProduct != null) {
        final branchStockChanged = await txn.rawUpdate(
          'UPDATE branch_stock SET quantity = quantity + ?, updatedAt = ? '
          'WHERE branchId = ? AND productId = ?',
          [quantity, returnedAt.toIso8601String(), bill.branchId, resolvedProduct.id],
        );
        if (branchStockChanged != 1) {
          throw StateError('Branch stock record is missing; return was cancelled to avoid inconsistent stock.');
        }
      }
      await txn.insert('bill_returns', returnRow);
      if (cashRefundRow != null) {
        await txn.insert('branch_cash_transactions', cashRefundRow);
      }
      if (customerRefundRow != null) {
        await txn.insert('customer_ledger', customerRefundRow);
      }
      await txn.insert('daily_sales', returnSale.toMap());
    });

    if (resolvedProduct != null && newStock != null) {
      inventory.applyStockAfterTransaction(resolvedProduct.id, newStock!);
    }
    await _queueSafely(
      operation: 'create', tableName: 'returns', documentId: returnId, data: isManualLine ? {...returnRow, 'isManual': true} : returnRow);
    await _queueSafely(
      operation: 'create', tableName: 'sales', documentId: returnSale.id, data: returnSale.toMap());
    if (cashRefundRow != null) {
      await _queueSafely(
        operation: 'create',
        tableName: 'branch_cash_transactions',
        documentId: cashRefundRow['id'] as String,
        data: cashRefundRow,
      );
    }
    if (customerRefundRow != null) {
      await _queueSafely(
        operation: 'create',
        tableName: 'customer_ledger',
        documentId: customerRefundRow['id'] as String,
        data: customerRefundRow,
      );
    }
    if (resolvedProduct != null && newStock != null) {
      await _queueSafely(
        operation: 'update',
        tableName: 'products',
        documentId: resolvedProduct.id,
        data: Product(
          id: resolvedProduct.id,
          name: resolvedProduct.name,
          category: resolvedProduct.category,
          stockQuantity: newStock!,
          costPrice: resolvedProduct.costPrice,
          sellingPrice: resolvedProduct.sellingPrice,
          lowStockThreshold: resolvedProduct.lowStockThreshold,
          barcode: resolvedProduct.barcode,
          expiryDate: resolvedProduct.expiryDate,
        ).toMap(),
      );
    }
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
        final itemRows = await db.query(
          'bill_items',
          where: 'billId = ?',
          whereArgs: [billId],
          orderBy: 'id ASC',
        );
        final items = itemRows.map((r) => BillItem.fromMap(r)).toList(growable: false);
        loadedBills.add(billFromDatabaseRow(row, items));
        loadedItems[billId] = items;
      }
      // Replace the visible history only after every row has been parsed.
      // A read/parse failure must not silently turn the list into "no bills".
      savedBills
        ..clear()
        ..addAll(loadedBills);
      _billItemsCache
        ..clear()
        ..addAll(loadedItems);
    } catch (error, stackTrace) {
      historyLoadError = error.toString();
      debugPrint('[PosProvider] Failed to load bill history: $error\\n$stackTrace');
    } finally {
      isLoadingHistory = false;
      notifyListeners();
    }
  }

  List<Bill> filterHistory({DateTime? date, String? customer, double? minAmount}) => savedBills.where((b) {
    final matchesDate = date == null || (b.date.year == date.year && b.date.month == date.month && b.date.day == date.day);
    final matchesCustomer = customer == null || customer.isEmpty || (b.customerName?.toLowerCase().contains(customer.toLowerCase()) ?? false);
    final matchesAmount = minAmount == null || b.grandTotal >= minAmount;
    return matchesDate && matchesCustomer && matchesAmount;
  }).toList();
}