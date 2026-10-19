import 'package:uuid/uuid.dart';

import 'db_service.dart';

class PaymentLine {
  final String method;
  final double amount;
  final String? reference;

  const PaymentLine({required this.method, required this.amount, this.reference});
}

class ReturnLine {
  final String? productId;
  final String productName;
  final String? imei;
  final int quantity;
  final double unitPrice;

  const ReturnLine({
    this.productId,
    required this.productName,
    this.imei,
    required this.quantity,
    required this.unitPrice,
  });

  double get total => quantity * unitPrice;
}

/// Transaction-safe business operations used by customer, checkout, returns,
/// and branch management screens.
class BusinessOperationsService {
  BusinessOperationsService._();
  static final instance = BusinessOperationsService._();
  final _uuid = const Uuid();

  Future<String> addCustomer({
    required String name,
    String? phone,
    String? address,
    String? email,
  }) async {
    if (name.trim().isEmpty) throw ArgumentError('Customer name is required.');
    final id = _uuid.v4();
    final db = await DBService.instance.database;
    await db.insert('customers', {
      'id': id,
      'name': name.trim(),
      'phone': phone,
      'address': address,
      'email': email,
      'createdAt': DateTime.now().toIso8601String(),
    });
    return id;
  }

  /// Positive credit increases what the customer owes; payment reduces it.
  Future<void> recordCustomerLedgerEntry({
    required String customerId,
    required String type,
    required double amount,
    String? referenceId,
    String? note,
    DateTime? date,
  }) async {
    if (!{'credit', 'payment', 'refund', 'adjustment'}.contains(type)) {
      throw ArgumentError('Unsupported ledger entry type: $type');
    }
    if (amount <= 0) throw ArgumentError.value(amount, 'amount', 'Must be positive.');
    final db = await DBService.instance.database;
    final customer = await db.query('customers',
        columns: ['id'], where: 'id = ?', whereArgs: [customerId], limit: 1);
    if (customer.isEmpty) throw StateError('Customer not found.');
    await db.insert('customer_ledger', {
      'id': _uuid.v4(),
      'customerId': customerId,
      'date': (date ?? DateTime.now()).toIso8601String(),
      'type': type == 'credit' ? 'sale_due' : type,
      'amount': amount,
      'referenceId': referenceId,
      'note': note,
    });
  }

  Future<double> customerBalance(String customerId) async {
    final db = await DBService.instance.database;
    final rows = await db.query('customer_ledger',
        where: 'customerId = ?', whereArgs: [customerId]);
    var balance = 0.0;
    for (final row in rows) {
      final amount = (row['amount'] as num).toDouble();
      switch (row['type']) {
        case 'credit':
          balance += amount;
          break;
        case 'payment':
        case 'refund':
          balance -= amount;
          break;
        case 'adjustment':
          balance += amount;
          break;
      }
    }
    return balance;
  }

  /// Stores split tender only when the sum matches the bill total.
  Future<void> recordSplitPayment({
    required String billId,
    required double billTotal,
    required List<PaymentLine> payments,
  }) async {
    if (payments.isEmpty || payments.any((p) => p.amount <= 0 || p.method.trim().isEmpty)) {
      throw ArgumentError('Each payment needs a method and a positive amount.');
    }
    final paid = payments.fold<double>(0, (sum, p) => sum + p.amount);
    if ((paid - billTotal).abs() > 0.01) {
      throw StateError('Payment total ($paid) must equal bill total ($billTotal).');
    }
    final db = await DBService.instance.database;
    await db.transaction((txn) async {
      final bill = await txn.query('bills',
          where: 'id = ?', whereArgs: [billId], limit: 1);
      if (bill.isEmpty) throw StateError('Bill not found.');
      final billItems = await txn.query('bill_items',
          where: 'billId = ?', whereArgs: [billId]);
      final subtotal = billItems.fold<double>(0, (sum, item) =>
          sum + (item['quantity'] as num).toDouble() * (item['unitPrice'] as num).toDouble());
      final discount = (bill.first['discount'] as num?)?.toDouble() ?? 0;
      final taxPercent = (bill.first['taxPercent'] as num?)?.toDouble() ?? 0;
      final storedTotal = (subtotal - discount) + ((subtotal - discount) * taxPercent / 100);
      if ((storedTotal - billTotal).abs() > 0.01) {
        throw StateError('Supplied bill total does not match the saved bill total.');
      }
      final existing = await txn.query('payments',
          columns: ['id'], where: 'billId = ?', whereArgs: [billId], limit: 1);
      if (existing.isNotEmpty) throw StateError('Payments already recorded for this bill.');
      for (final payment in payments) {
        await txn.insert('payments', {
          'id': _uuid.v4(),
          'billId': billId,
          'method': payment.method.trim(),
          'amount': payment.amount,
          'reference': payment.reference,
        });
      }
    });
  }

  /// Restores stock and writes the return/refund record in one SQLite
  /// transaction. Returns cannot exceed the originally sold, not-yet-returned
  /// quantity for a product on the bill.
  Future<String> processReturn({
    required String billId,
    required List<ReturnLine> items,
    required double refundAmount,
    String? customerName,
    String? reason,
    String? customerId,
    DateTime? date,
  }) async {
    if (items.isEmpty || items.any((i) => i.quantity <= 0 || i.unitPrice < 0)) {
      throw ArgumentError('Return items must have positive quantities and valid prices.');
    }
    final calculated = items.fold<double>(0, (sum, item) => sum + item.total);
    if (refundAmount < 0 || refundAmount - calculated > 0.01) {
      throw ArgumentError('Refund cannot exceed the value of returned items.');
    }
    final db = await DBService.instance.database;
    final returnId = _uuid.v4();
    await db.transaction((txn) async {
      final billRows = await txn.query('bills',
          where: 'id = ?', whereArgs: [billId], limit: 1);
      if (billRows.isEmpty) throw StateError('Original bill not found.');
      final branchId = billRows.first['branchId'] as String?;
      for (final item in items.where((item) => item.imei != null)) {
        final soldDevice = await txn.query('mobile_devices',
            where: 'imei1 = ? AND soldBillId = ? AND status = ?',
            whereArgs: [item.imei, billId, 'sold'], limit: 1);
        if (soldDevice.isEmpty) {
          throw StateError('IMEI ${item.imei} was not sold on this bill or has already been returned.');
        }
        final soldItem = await txn.query('bill_items',
            where: 'billId = ? AND mobileImei = ?', whereArgs: [billId, item.imei], limit: 1);
        if (soldItem.isEmpty) throw StateError('IMEI ${item.imei} is not part of this bill.');
      }
      final requestedReturns = <String, int>{};
      for (final item in items) {
        requestedReturns.update(item.productName, (quantity) => quantity + item.quantity,
            ifAbsent: () => item.quantity);
      }
      for (final entry in requestedReturns.entries) {
        final soldRows = await txn.rawQuery(
          'SELECT COALESCE(SUM(quantity), 0) AS qty FROM bill_items WHERE billId = ? AND productName = ?',
          [billId, entry.key],
        );
        final sold = (soldRows.first['qty'] as num).toInt();
        final returnedRows = await txn.rawQuery(
          'SELECT COALESCE(SUM(ri.quantity), 0) AS qty FROM return_items ri JOIN returns r ON r.id = ri.returnId WHERE r.billId = ? AND ri.productName = ?',
          [billId, entry.key],
        );
        final alreadyReturned = (returnedRows.first['qty'] as num).toInt();
        if (entry.value + alreadyReturned > sold) {
          throw StateError('Return quantity exceeds remaining sold quantity for ${entry.key}.');
        }
      }

      await txn.insert('returns', {
        'id': returnId,
        'billId': billId,
        'date': (date ?? DateTime.now()).toIso8601String(),
        'customerName': customerName,
        'refundAmount': refundAmount,
        'reason': reason,
      });
      for (var index = 0; index < items.length; index++) {
        final item = items[index];
        await txn.insert('return_items', {
          'id': _uuid.v4(),
          'returnId': returnId,
          'productId': item.productId,
          'productName': item.productName,
          'imei': item.imei,
          'quantity': item.quantity,
          'unitPrice': item.unitPrice,
        });
        String? resolvedProductId = item.productId;
        if (item.imei != null && resolvedProductId == null) {
          final devices = await txn.query('mobile_devices',
              columns: ['productId'], where: 'imei = ?', whereArgs: [item.imei], limit: 1);
          if (devices.isNotEmpty) resolvedProductId = devices.first['productId'] as String?;
        }
        final products = resolvedProductId != null
            ? await txn.query('products', where: 'id = ?', whereArgs: [resolvedProductId], limit: 1)
            : await txn.query('products', where: 'name = ?', whereArgs: [item.productName], limit: 1);
        if (products.isEmpty || products.first['name'] != item.productName) {
          throw StateError('Product not found or does not match returned item: ${item.productName}.');
        }
        final product = products.first;
        if (item.imei != null) {
          await txn.update('mobile_devices', {
            'status': 'returned', 'branchId': branchId,
          }, where: 'imei1 = ? AND soldBillId = ? AND status = ?',
              whereArgs: [item.imei, billId, 'sold']);
        }
        if (branchId != null) {
          final branchRows = await txn.query('branch_stock',
              where: 'branchId = ? AND productId = ?',
              whereArgs: [branchId, product['id']], limit: 1);
          if (branchRows.isEmpty) {
            await txn.insert('branch_stock', {
              'branchId': branchId, 'productId': product['id'],
              'quantity': item.quantity, 'updatedAt': DateTime.now().toIso8601String(),
            });
          } else {
            final oldQty = (branchRows.first['quantity'] as num).toInt();
            await txn.update('branch_stock', {'quantity': oldQty + item.quantity, 'updatedAt': DateTime.now().toIso8601String()},
                where: 'branchId = ? AND productId = ?', whereArgs: [branchId, product['id']]);
          }
        } else {
          final oldQty = (product['stockQuantity'] as num).toInt();
          await txn.update('products', {'stockQuantity': oldQty + item.quantity},
              where: 'id = ?', whereArgs: [product['id']]);
        }
      }
      if (customerId != null && refundAmount > 0) {
        await txn.insert('customer_ledger', {
          'id': _uuid.v4(),
          'customerId': customerId,
          'date': (date ?? DateTime.now()).toIso8601String(),
          'type': 'refund',
          'amount': refundAmount,
          'referenceId': returnId,
          'note': 'Refund for bill $billId',
        });
      }
    });
    return returnId;
  }

  Future<String> createBranch({required String name, String? address, String? phone}) async {
    if (name.trim().isEmpty) throw ArgumentError('Branch name is required.');
    final id = _uuid.v4();
    final db = await DBService.instance.database;
    await db.insert('branches', {
      'id': id, 'name': name.trim(), 'code': 'BR-${id.substring(0, 8).toUpperCase()}',
      'address': address, 'phone': phone, 'isMain': 0, 'isActive': 1,
      'createdAt': DateTime.now().toIso8601String(),
    });
    return id;
  }

  Future<void> setBranchStock({
    required String branchId,
    required String productId,
    required int quantity,
  }) async {
    if (quantity < 0) throw ArgumentError.value(quantity, 'quantity', 'Cannot be negative.');
    final db = await DBService.instance.database;
    await db.transaction((txn) async {
      final branch = await txn.query('branches', where: 'id = ?', whereArgs: [branchId], limit: 1);
      final product = await txn.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
      if (branch.isEmpty || product.isEmpty) throw StateError('Branch or product not found.');
      final rows = await txn.query('branch_stock',
          where: 'branchId = ? AND productId = ?', whereArgs: [branchId, productId], limit: 1);
      if (rows.isEmpty) {
        await txn.insert('branch_stock', {'branchId': branchId, 'productId': productId, 'quantity': quantity, 'updatedAt': DateTime.now().toIso8601String()});
      } else {
        await txn.update('branch_stock', {'quantity': quantity, 'updatedAt': DateTime.now().toIso8601String()},
            where: 'branchId = ? AND productId = ?', whereArgs: [branchId, productId]);
      }
    });
  }

  Future<void> recordBranchCash({
    required String branchId,
    required String type,
    required double amount,
    String? note,
    DateTime? date,
  }) async {
    if (!{'in', 'out'}.contains(type) || amount <= 0) {
      throw ArgumentError('Cash type must be in/out and amount must be positive.');
    }
    final db = await DBService.instance.database;
    final branch = await db.query('branches', where: 'id = ?', whereArgs: [branchId], limit: 1);
    if (branch.isEmpty) throw StateError('Branch not found.');
    await db.insert('branch_cash_entries', {
      'id': _uuid.v4(), 'branchId': branchId,
      'date': (date ?? DateTime.now()).toIso8601String(),
      'type': type, 'amount': amount, 'note': note,
    });
  }

  Future<Map<String, dynamic>> branchReport(String branchId) async {
    final db = await DBService.instance.database;
    final branchRows = await db.query('branches', where: 'id = ?', whereArgs: [branchId], limit: 1);
    if (branchRows.isEmpty) throw StateError('Branch not found.');
    final stockRows = await db.rawQuery(
      'SELECT COALESCE(SUM(quantity), 0) AS units FROM branch_stock WHERE branchId = ?', [branchId]);
    final cashRows = await db.query('branch_cash_entries', where: 'branchId = ?', whereArgs: [branchId]);
    var cashBalance = 0.0;
    for (final row in cashRows) {
      final amount = (row['amount'] as num).toDouble();
      cashBalance += row['type'] == 'in' ? amount : -amount;
    }
    return {'branch': branchRows.first, 'stockUnits': (stockRows.first['units'] as num).toInt(), 'cashBalance': cashBalance};
  }

  Future<String> addMobileDevice({
    required String imei,
    String? productId,
    String? serialNumber,
    double purchasePrice = 0,
    double salePrice = 0,
    String? branchId,
  }) async {
    final normalizedImei = imei.replaceAll(RegExp(r'\s+'), '');
    if (!RegExp(r'^\d{15}$').hasMatch(normalizedImei)) {
      throw ArgumentError('IMEI must contain exactly 15 digits.');
    }
    final id = _uuid.v4();
    final db = await DBService.instance.database;
    final products = productId == null ? <Map<String, Object?>>[] : await db.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
    final product = products.isEmpty ? <String, Object?>{} : products.first;
    final now = DateTime.now().toIso8601String();
    await db.insert('mobile_devices', {
      'id': id, 'deviceType': 'new', 'brand': product['name'] ?? 'Unknown',
      'model': product['name'] ?? 'Tracked device', 'imei1': normalizedImei,
      'serialNumber': serialNumber, 'status': 'in_stock',
      'purchasePrice': purchasePrice, 'sellingPrice': salePrice,
      'branchId': branchId, 'inspectionJson': '{}', 'createdAt': now, 'updatedAt': now,
    });
    return id;
  }

  Future<void> markMobileDeviceSold({required String imei, required String billId}) async {
    final db = await DBService.instance.database;
    await db.transaction((txn) async {
      final devices = await txn.query('mobile_devices', where: 'imei1 = ?', whereArgs: [imei], limit: 1);
      final bill = await txn.query('bills', where: 'id = ?', whereArgs: [billId], limit: 1);
      if (devices.isEmpty || bill.isEmpty) throw StateError('IMEI device or bill not found.');
      if (devices.first['status'] != 'in_stock') throw StateError('This IMEI device is not available for sale.');
      await txn.update('mobile_devices', {'status': 'sold', 'soldBillId': billId, 'soldAt': DateTime.now().toIso8601String(), 'updatedAt': DateTime.now().toIso8601String()},
          where: 'id = ?', whereArgs: [devices.first['id']]);
    });
  }

  Future<String> addTransportTicket({
    required String routeId,
    required String passengerName,
    required String travelDate,
    required double fare,
    String? seatNumber,
  }) async {
    if (passengerName.trim().isEmpty || fare < 0) throw ArgumentError('Passenger and fare are required.');
    final db = await DBService.instance.database;
    final route = await db.query('transport_routes', where: 'id = ?', whereArgs: [routeId], limit: 1);
    if (route.isEmpty) throw StateError('Route not found.');
    if (seatNumber != null && seatNumber.isNotEmpty) {
      final occupied = await db.query('transport_tickets',
          where: 'routeId = ? AND travelDate = ? AND seatNumber = ? AND status = ?',
          whereArgs: [routeId, travelDate, seatNumber, 'booked'], limit: 1);
      if (occupied.isNotEmpty) throw StateError('Seat already booked for this route and date.');
    }
    final id = _uuid.v4();
    await db.insert('transport_tickets', {
      'id': id, 'routeId': routeId, 'passengerName': passengerName.trim(),
      'seatNumber': seatNumber, 'travelDate': travelDate, 'fare': fare, 'status': 'booked',
    });
    return id;
  }

  Future<String> addProductVariant({
    required String productId,
    String? size,
    String? color,
    String? sku,
    int quantity = 0,
  }) async {
    if (quantity < 0) throw ArgumentError('Variant quantity cannot be negative.');
    final db = await DBService.instance.database;
    final product = await db.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
    if (product.isEmpty) throw StateError('Parent product not found.');
    final id = _uuid.v4();
    await db.insert('product_variants', {
      'id': id, 'productId': productId, 'size': size, 'color': color,
      'sku': sku, 'quantity': quantity,
    });
    return id;
  }

  Future<String> createRestaurantTable({required String name, int capacity = 2}) async {
    if (name.trim().isEmpty || capacity < 1) throw ArgumentError('Table name and positive capacity are required.');
    final id = _uuid.v4();
    final db = await DBService.instance.database;
    await db.insert('restaurant_tables', {
      'id': id, 'name': name.trim(), 'capacity': capacity, 'status': 'available',
    });
    return id;
  }

  Future<String> createRestaurantOrder({String? tableId, double total = 0}) async {
    if (total < 0) throw ArgumentError('Order total cannot be negative.');
    final db = await DBService.instance.database;
    final id = _uuid.v4();
    await db.transaction((txn) async {
      if (tableId != null) {
        final tables = await txn.query('restaurant_tables',
            where: 'id = ?', whereArgs: [tableId], limit: 1);
        if (tables.isEmpty) throw StateError('Restaurant table not found.');
        if (tables.first['status'] != 'available') throw StateError('Restaurant table is already occupied.');
        await txn.update('restaurant_tables', {'status': 'occupied'},
            where: 'id = ?', whereArgs: [tableId]);
      }
      await txn.insert('restaurant_orders', {
        'id': id, 'tableId': tableId, 'status': 'open',
        'total': total, 'createdAt': DateTime.now().toIso8601String(),
      });
    });
    return id;
  }

  Future<String> addVehicleRecord({
    required String type,
    String? make,
    String? model,
    String? registrationNumber,
    String? vin,
    double purchasePrice = 0,
    double salePrice = 0,
  }) async {
    if (type.trim().isEmpty) throw ArgumentError('Vehicle type is required.');
    final db = await DBService.instance.database;
    final id = _uuid.v4();
    await db.insert('vehicle_records', {
      'id': id, 'type': type.trim(), 'make': make, 'model': model,
      'registrationNumber': registrationNumber, 'vin': vin,
      'status': 'in_stock', 'purchasePrice': purchasePrice, 'salePrice': salePrice,
    });
    return id;
  }

  Future<String> addTransportRoute({
    required String name,
    String? origin,
    String? destination,
  }) async {
    if (name.trim().isEmpty) throw ArgumentError('Route name is required.');
    final id = _uuid.v4();
    final db = await DBService.instance.database;
    await db.insert('transport_routes', {
      'id': id, 'name': name.trim(), 'origin': origin, 'destination': destination,
    });
    return id;
  }

  Future<String> createCargoJob({
    String? routeId,
    required String customerName,
    String? loadDescription,
    required double weight,
    required double freightAmount,
  }) async {
    if (customerName.trim().isEmpty || weight < 0 || freightAmount < 0) {
      throw ArgumentError('Customer, non-negative weight, and freight amount are required.');
    }
    final db = await DBService.instance.database;
    if (routeId != null) {
      final routes = await db.query('transport_routes', where: 'id = ?', whereArgs: [routeId], limit: 1);
      if (routes.isEmpty) throw StateError('Route not found.');
    }
    final id = _uuid.v4();
    final trackingToken = '${_uuid.v4()}${_uuid.v4()}';
    await db.insert('cargo_jobs', {
      'id': id, 'routeId': routeId, 'customerName': customerName.trim(),
      'loadDescription': loadDescription, 'weight': weight,
      'freightAmount': freightAmount, 'status': 'created',
      'trackingToken': trackingToken,
    });
    return id;
  }

  Future<String> createServiceJob({
    required String customerName,
    String? deviceOrVehicle,
    required String issue,
    double estimatedCost = 0,
  }) async {
    if (customerName.trim().isEmpty || issue.trim().isEmpty || estimatedCost < 0) {
      throw ArgumentError('Customer, issue, and non-negative estimated cost are required.');
    }
    final id = _uuid.v4();
    final db = await DBService.instance.database;
    await db.insert('service_jobs', {
      'id': id, 'customerName': customerName.trim(),
      'deviceOrVehicle': deviceOrVehicle, 'issue': issue.trim(),
      'status': 'received', 'estimatedCost': estimatedCost,
      'finalCost': 0, 'createdAt': DateTime.now().toIso8601String(),
    });
    return id;
  }

  Future<String> addSparePartCompatibility({
    required String productId,
    required String partType,
    String? make,
    String? model,
    int? yearFrom,
    int? yearTo,
    String? engineCode,
    String? notes,
  }) async {
    const supportedTypes = {'bike', 'car', 'mobile', 'other'};
    if (!supportedTypes.contains(partType.toLowerCase())) {
      throw ArgumentError('Part type must be bike, car, mobile, or other.');
    }
    if (yearFrom != null && yearTo != null && yearFrom > yearTo) {
      throw ArgumentError('Year-from cannot be after year-to.');
    }
    final db = await DBService.instance.database;
    final products = await db.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
    if (products.isEmpty) throw StateError('Spare-part product not found.');
    final id = _uuid.v4();
    await db.insert('spare_part_compatibility', {
      'id': id, 'productId': productId, 'partType': partType.toLowerCase(),
      'make': make, 'model': model, 'yearFrom': yearFrom, 'yearTo': yearTo,
      'engineCode': engineCode, 'notes': notes,
    });
    return id;
  }

  Future<String> addRestaurantMenuItem({required String name, String? category, required double price}) async {
    if (name.trim().isEmpty || price < 0) throw ArgumentError('Menu item name and non-negative price are required.');
    final id = _uuid.v4(); await (await DBService.instance.database).insert('restaurant_menu_items', {'id': id, 'name': name.trim(), 'category': category, 'price': price, 'active': 1}); return id;
  }
  Future<String> addRestaurantOrderItem({required String orderId, required String menuItemId, required int quantity, String? notes}) async {
    if (quantity < 1) throw ArgumentError('Quantity must be at least one.');
    final db = await DBService.instance.database; final id = _uuid.v4();
    await db.transaction((txn) async {
      final orders = await txn.query('restaurant_orders', where: 'id = ?', whereArgs: [orderId], limit: 1);
      final menu = await txn.query('restaurant_menu_items', where: 'id = ? AND active = 1', whereArgs: [menuItemId], limit: 1);
      if (orders.isEmpty || menu.isEmpty || orders.first['status'] != 'open') throw StateError('Open order and active menu item required.');
      await txn.insert('restaurant_order_items', {'id': id, 'orderId': orderId, 'menuItemId': menuItemId, 'quantity': quantity, 'unitPrice': menu.first['price'], 'notes': notes, 'kitchenStatus': 'queued'});
      final items = await txn.query('restaurant_order_items', where: 'orderId = ?', whereArgs: [orderId]);
      final total = items.fold<double>(0, (sum, row) => sum + (row['quantity'] as num).toDouble() * (row['unitPrice'] as num).toDouble());
      await txn.update('restaurant_orders', {'total': total}, where: 'id = ?', whereArgs: [orderId]);
    }); return id;
  }
  Future<void> updateKitchenStatus({required String orderItemId, required String status}) async {
    if (!{'queued','preparing','ready','served','cancelled'}.contains(status)) throw ArgumentError('Invalid kitchen status.');
    final changed = await (await DBService.instance.database).update('restaurant_order_items', {'kitchenStatus': status}, where: 'id = ?', whereArgs: [orderItemId]);
    if (changed != 1) throw StateError('Restaurant order item not found.');
  }
  /// Records one or more restaurant tenders atomically. The total must match
  /// the current saved order total, and a second payment attempt is rejected.
  Future<void> recordRestaurantPayment({
    required String orderId,
    required List<PaymentLine> payments,
  }) async {
    if (payments.isEmpty ||
        payments.any((p) => p.method.trim().isEmpty || p.amount <= 0)) {
      throw ArgumentError('Each restaurant payment needs a method and positive amount.');
    }
    final paid = payments.fold<double>(0, (sum, payment) => sum + payment.amount);
    final db = await DBService.instance.database;
    await db.transaction((txn) async {
      final orders = await txn.query('restaurant_orders',
          where: 'id = ?', whereArgs: [orderId], limit: 1);
      if (orders.isEmpty || orders.first['status'] != 'open') {
        throw StateError('An open restaurant order is required for payment.');
      }
      final total = (orders.first['total'] as num).toDouble();
      if ((paid - total).abs() > 0.01) {
        throw StateError('Payment total ($paid) must equal order total ($total).');
      }
      final existing = await txn.query('restaurant_order_payments',
          columns: ['id'], where: 'orderId = ?', whereArgs: [orderId], limit: 1);
      if (existing.isNotEmpty) {
        throw StateError('Restaurant order payment has already been recorded.');
      }
      for (final payment in payments) {
        await txn.insert('restaurant_order_payments', {
          'id': _uuid.v4(),
          'orderId': orderId,
          'method': payment.method.trim(),
          'amount': payment.amount,
          'reference': payment.reference,
          'paidAt': DateTime.now().toIso8601String(),
        });
      }
    });
  }

  Future<void> completeRestaurantOrder(String orderId) async {
    final db = await DBService.instance.database;
    await db.transaction((txn) async {
      final rows = await txn.query('restaurant_orders', where: 'id = ?', whereArgs: [orderId], limit: 1);
      if (rows.isEmpty) throw StateError('Restaurant order not found.');
      final pending = await txn.query('restaurant_order_items',
          where: 'orderId = ? AND kitchenStatus NOT IN (?, ?)',
          whereArgs: [orderId, 'served', 'cancelled']);
      if (pending.isNotEmpty) {
        throw StateError('Kitchen items must be served or cancelled before closing.');
      }
      final total = (rows.first['total'] as num).toDouble();
      if (total > 0) {
        final payments = await txn.query('restaurant_order_payments',
            where: 'orderId = ?', whereArgs: [orderId]);
        final paid = payments.fold<double>(0, (sum, payment) =>
            sum + (payment['amount'] as num).toDouble());
        if ((paid - total).abs() > 0.01) {
          throw StateError('Restaurant order must be paid in full before closing.');
        }
      }
      await txn.update('restaurant_orders', {'status':'completed'}, where:'id = ?', whereArgs:[orderId]);
      final tableId = rows.first['tableId'] as String?; if (tableId != null) await txn.update('restaurant_tables', {'status':'available'}, where:'id = ?', whereArgs:[tableId]);
    });
  }
  Future<void> recordVehicleTransaction({required String vehicleId, required String type, required String partyName, required double amount, String? notes}) async {
    if (!{'purchase', 'sale', 'expense'}.contains(type) ||
        amount <= 0 || partyName.trim().isEmpty) {
      throw ArgumentError('Valid transaction type, party and positive amount required.');
    }
    final db = await DBService.instance.database;
    await db.transaction((txn) async {
      final rows = await txn.query('vehicle_records',
          where: 'id = ?', whereArgs: [vehicleId], limit: 1);
      if (rows.isEmpty) throw StateError('Vehicle not found.');
      final vehicle = rows.first;
      if (type == 'sale' && vehicle['status'] != 'in_stock') {
        throw StateError('Only an in-stock vehicle can be sold.');
      }
      if (type == 'purchase' && vehicle['status'] != 'in_stock') {
        throw StateError('A sold vehicle cannot be purchased again.');
      }
      await txn.insert('vehicle_transactions', {
        'id': _uuid.v4(),
        'vehicleId': vehicleId,
        'type': type,
        'partyName': partyName.trim(),
        'transactionDate': DateTime.now().toIso8601String(),
        'amount': amount,
        'notes': notes,
      });
      if (type == 'sale') {
        await txn.update('vehicle_records', {'status': 'sold', 'salePrice': amount},
            where: 'id = ?', whereArgs: [vehicleId]);
        final purchaseCost = (vehicle['purchasePrice'] as num?)?.toDouble() ?? 0;
        final vehicleName = '${vehicle['make'] ?? ''} ${vehicle['model'] ?? ''} ${vehicle['registrationNumber'] ?? vehicleId}'.trim();
        await txn.insert('daily_sales', {
          'id': _uuid.v4(),
          'date': DateTime.now().toIso8601String(),
          'productName': 'Vehicle sale: $vehicleName',
          'costPrice': purchaseCost,
          'salePrice': amount,
        });
      } else if (type == 'purchase') {
        final previousPurchases = await txn.query('vehicle_transactions',
            columns: ['id'], where: 'vehicleId = ? AND type = ?', whereArgs: [vehicleId, 'purchase'], limit: 1);
        if (previousPurchases.length > 1) {
          throw StateError('Vehicle purchase has already been recorded.');
        }
        await txn.update('vehicle_records', {'purchasePrice': amount},
            where: 'id = ?', whereArgs: [vehicleId]);
        await txn.insert('expenses', {
          'id': _uuid.v4(),
          'date': DateTime.now().toIso8601String(),
          'label': 'Vehicle purchase: ${vehicle['make'] ?? ''} ${vehicle['model'] ?? ''} · ${partyName.trim()}',
          'amount': amount,
        });
      } else {
        await txn.insert('expenses', {
          'id': _uuid.v4(),
          'date': DateTime.now().toIso8601String(),
          'label': 'Vehicle expense: ${vehicle['make'] ?? ''} ${vehicle['model'] ?? ''} · ${partyName.trim()}',
          'amount': amount,
        });
      }
    });
  }

  /// Calculates realized gross profit per vehicle from the ledger transactions.
  /// Net profit = sale proceeds - recorded purchases - recorded expenses.
  Future<List<Map<String, Object?>>> vehicleProfitReport() async {
    final db = await DBService.instance.database;
    return db.rawQuery('''
      SELECT v.id AS vehicleId, v.make, v.model, v.registrationNumber,
        v.status,
        COALESCE(SUM(CASE WHEN t.type = 'sale' THEN t.amount ELSE 0 END), 0) AS saleProceeds,
        COALESCE(NULLIF(SUM(CASE WHEN t.type = 'purchase' THEN t.amount ELSE 0 END), 0), v.purchasePrice, 0) AS purchaseCost,
        COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount ELSE 0 END), 0) AS expenses,
        COALESCE(SUM(CASE WHEN t.type = 'sale' THEN t.amount ELSE 0 END), 0)
          - COALESCE(NULLIF(SUM(CASE WHEN t.type = 'purchase' THEN t.amount ELSE 0 END), 0), v.purchasePrice, 0)
          - COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount ELSE 0 END), 0) AS netProfit
      FROM vehicle_records v
      LEFT JOIN vehicle_transactions t ON t.vehicleId = v.id
      GROUP BY v.id, v.make, v.model, v.registrationNumber, v.status
      ORDER BY v.make, v.model
    ''');
  }
  Future<void> updateCargoStatus({required String cargoId, required String status, String? location, String? note}) async {
    if (!{'created','picked_up','in_transit','at_hub','out_for_delivery','delivered','cancelled'}.contains(status)) throw ArgumentError('Invalid cargo status.');
    final db = await DBService.instance.database;
    await db.transaction((txn) async {
      if ((await txn.query('cargo_jobs', where:'id = ?', whereArgs:[cargoId], limit:1)).isEmpty) throw StateError('Cargo job not found.');
      await txn.update('cargo_jobs', {'status':status}, where:'id = ?', whereArgs:[cargoId]);
      await txn.insert('cargo_status_history', {'id':_uuid.v4(),'cargoId':cargoId,'status':status,'location':location,'note':note,'recordedAt':DateTime.now().toIso8601String()});
    });
  }
  Future<String> addSchoolStudent({required String name, String? guardianName, String? phone, String? className}) async {
    if (name.trim().isEmpty) throw ArgumentError('Student name required.'); final id=_uuid.v4();
    await (await DBService.instance.database).insert('school_students', {'id':id,'name':name.trim(),'guardianName':guardianName,'phone':phone,'className':className,'admissionDate':DateTime.now().toIso8601String(),'status':'active'}); return id;
  }
  Future<String> addSchoolFee({required String studentId, required double amount, double paidAmount=0, String? note}) async {
    if (amount<0 || paidAmount<0 || paidAmount>amount) throw ArgumentError('Invalid fee amount/payment.');
    final db=await DBService.instance.database; if ((await db.query('school_students',where:'id = ?',whereArgs:[studentId],limit:1)).isEmpty) throw StateError('Student not found.');
    final id=_uuid.v4(); await db.insert('school_fees',{'id':id,'studentId':studentId,'dueDate':DateTime.now().toIso8601String(),'amount':amount,'paidAmount':paidAmount,'status':paidAmount>=amount?'paid':'due','note':note}); return id;
  }
  Future<void> recordSchoolFeePayment({required String feeId, required double amount}) async {
    if (amount <= 0) throw ArgumentError('Payment amount must be positive.');
    final db = await DBService.instance.database;
    await db.transaction((txn) async {
      final rows = await txn.query('school_fees', where: 'id = ?', whereArgs: [feeId], limit: 1);
      if (rows.isEmpty) throw StateError('School fee not found.');
      final row = rows.single;
      final due = (row['amount'] as num).toDouble();
      final paid = (row['paidAmount'] as num).toDouble();
      if (paid + amount > due + 0.01) throw StateError('Payment exceeds outstanding fee.');
      final next = paid + amount;
      await txn.update('school_fees', {
        'paidAmount': next,
        'status': next >= due - 0.01 ? 'paid' : 'partial',
      }, where: 'id = ?', whereArgs: [feeId]);
    });
  }

  Future<void> updateClinicAppointmentStatus({required String appointmentId, required String status}) async {
    const allowed = {'scheduled', 'checked_in', 'completed', 'cancelled', 'no_show'};
    if (!allowed.contains(status)) throw ArgumentError('Invalid clinic appointment status.');
    final db = await DBService.instance.database;
    final count = await db.update('clinic_appointments', {'status': status},
        where: 'id = ? AND status NOT IN (?, ?)',
        whereArgs: [appointmentId, 'cancelled', 'completed']);
    if (count != 1) throw StateError('Appointment not found or already finalised.');
  }

  Future<void> recordClinicPayment({required String appointmentId, required double amount}) async {
    if (amount <= 0) throw ArgumentError('Payment amount must be positive.');
    final db = await DBService.instance.database;
    await db.transaction((txn) async {
      final rows = await txn.query('clinic_appointments', where: 'id = ?', whereArgs: [appointmentId], limit: 1);
      if (rows.isEmpty) throw StateError('Appointment not found.');
      final row = rows.single;
      final fee = (row['fee'] as num).toDouble();
      final paid = (row['paidAmount'] as num).toDouble();
      if (paid + amount > fee + 0.01) throw StateError('Payment exceeds appointment fee.');
      await txn.update('clinic_appointments', {'paidAmount': paid + amount},
          where: 'id = ?', whereArgs: [appointmentId]);
    });
  }

  Future<void> updateSalonBookingStatus({required String bookingId, required String status}) async {
    const allowed = {'booked', 'in_progress', 'completed', 'cancelled', 'no_show'};
    if (!allowed.contains(status)) throw ArgumentError('Invalid salon booking status.');
    final db = await DBService.instance.database;
    final count = await db.update('salon_bookings', {'status': status},
        where: 'id = ? AND status NOT IN (?, ?)',
        whereArgs: [bookingId, 'cancelled', 'completed']);
    if (count != 1) throw StateError('Booking not found or already finalised.');
  }

  Future<void> updateConstructionTaskStatus({required String taskId, required String status}) async {
    const allowed = {'todo', 'in_progress', 'completed', 'cancelled'};
    if (!allowed.contains(status)) throw ArgumentError('Invalid construction task status.');
    final db = await DBService.instance.database;
    final count = await db.update('construction_tasks', {'status': status},
        where: 'id = ? AND status NOT IN (?, ?)',
        whereArgs: [taskId, 'completed', 'cancelled']);
    if (count != 1) throw StateError('Task not found or already finalised.');
  }

  Future<void> updatePublicServiceCaseStatus({required String caseId, required String status}) async {
    const allowed = {'open', 'in_progress', 'resolved', 'rejected'};
    if (!allowed.contains(status)) throw ArgumentError('Invalid public service case status.');
    final db = await DBService.instance.database;
    final count = await db.update('public_service_cases', {'status': status},
        where: 'id = ? AND status NOT IN (?, ?)',
        whereArgs: [caseId, 'resolved', 'rejected']);
    if (count != 1) throw StateError('Case not found or already finalised.');
  }

  Future<Map<String, Object?>> businessVerticalReport() async {
    final db = await DBService.instance.database;
    final students = await db.rawQuery('SELECT COUNT(*) AS count, COALESCE(SUM(amount - paidAmount), 0) AS outstanding FROM school_fees');
    final clinic = await db.rawQuery('SELECT COUNT(*) AS count, COALESCE(SUM(fee - paidAmount), 0) AS outstanding FROM clinic_appointments');
    final salon = await db.rawQuery('SELECT COUNT(*) AS count, COALESCE(SUM(amount), 0) AS bookedValue FROM salon_bookings WHERE status != ?', ['cancelled']);
    final farm = await db.rawQuery('SELECT COUNT(*) AS count, COALESCE(SUM(cost), 0) AS cost FROM farm_activities');
    final construction = await db.rawQuery('SELECT COUNT(*) AS count, COALESCE(SUM(budget), 0) AS budget, COALESCE(SUM(spent), 0) AS spent FROM construction_projects');
    final publicCases = await db.rawQuery('SELECT COUNT(*) AS count, COALESCE(SUM(fee), 0) AS fees FROM public_service_cases');
    return {
      'school': students.single,
      'clinic': clinic.single,
      'salon': salon.single,
      'agriculture': farm.single,
      'construction': construction.single,
      'publicServices': publicCases.single,
    };
  }

  Future<String> addClinicPatient({required String name, String? phone, String? dateOfBirth, String? notes}) async {
    if(name.trim().isEmpty) throw ArgumentError('Patient name required.'); final id=_uuid.v4();
    await (await DBService.instance.database).insert('clinic_patients',{'id':id,'name':name.trim(),'phone':phone,'dateOfBirth':dateOfBirth,'notes':notes}); return id;
  }
  Future<String> bookClinicAppointment({required String patientId, required String appointmentAt, String? clinician, String? reason, required double fee}) async {
    if(fee<0) throw ArgumentError('Fee cannot be negative.'); final db=await DBService.instance.database;
    if((await db.query('clinic_patients',where:'id = ?',whereArgs:[patientId],limit:1)).isEmpty) throw StateError('Patient not found.');
    final id=_uuid.v4(); await db.insert('clinic_appointments',{'id':id,'patientId':patientId,'appointmentAt':appointmentAt,'clinician':clinician,'reason':reason,'status':'scheduled','fee':fee,'paidAmount':0}); return id;
  }
  Future<String> addSalonService({required String name, required int durationMinutes, required double price}) async {
    if(name.trim().isEmpty || durationMinutes<1 || price<0) throw ArgumentError('Invalid salon service.'); final id=_uuid.v4();
    await (await DBService.instance.database).insert('salon_services',{'id':id,'name':name.trim(),'durationMinutes':durationMinutes,'price':price,'active':1}); return id;
  }
  Future<String> bookSalonAppointment({required String customerName, String? phone, required String bookingAt, String? serviceId, String? staffName, required double amount}) async {
    if(customerName.trim().isEmpty || amount<0) throw ArgumentError('Invalid salon booking.'); final id=_uuid.v4();
    await (await DBService.instance.database).insert('salon_bookings',{'id':id,'customerName':customerName.trim(),'phone':phone,'serviceId':serviceId,'staffName':staffName,'bookingAt':bookingAt,'status':'booked','amount':amount}); return id;
  }
  Future<String> addFarmPlot({required String name, required double area, required String crop, String? season}) async {
    if(name.trim().isEmpty || area<=0 || crop.trim().isEmpty) throw ArgumentError('Plot, positive area and crop required.'); final id=_uuid.v4();
    await (await DBService.instance.database).insert('farm_plots',{'id':id,'name':name.trim(),'area':area,'areaUnit':'acre','crop':crop.trim(),'season':season,'status':'active'}); return id;
  }
  Future<String> recordFarmActivity({required String plotId, required String activityType, String? inputName, required double quantity, required double cost, String? notes}) async {
    if(activityType.trim().isEmpty || quantity<0 || cost<0) throw ArgumentError('Invalid farm activity.'); final db=await DBService.instance.database;
    if((await db.query('farm_plots',where:'id = ?',whereArgs:[plotId],limit:1)).isEmpty) throw StateError('Farm plot not found.');
    final id=_uuid.v4(); await db.insert('farm_activities',{'id':id,'plotId':plotId,'activityType':activityType.trim(),'activityDate':DateTime.now().toIso8601String(),'inputName':inputName,'quantity':quantity,'cost':cost,'notes':notes}); return id;
  }
  Future<String> addConstructionProject({required String name, String? clientName, String? location, required double budget, String? dueDate}) async {
    if(name.trim().isEmpty || budget<0) throw ArgumentError('Invalid project.'); final id=_uuid.v4();
    await (await DBService.instance.database).insert('construction_projects',{'id':id,'name':name.trim(),'clientName':clientName,'location':location,'budget':budget,'spent':0,'status':'planned','startDate':DateTime.now().toIso8601String(),'dueDate':dueDate}); return id;
  }
  Future<String> addConstructionTask({required String projectId, required String title, String? assignedTo, String? dueDate, required double cost}) async {
    if(title.trim().isEmpty || cost<0) throw ArgumentError('Invalid task.'); final db=await DBService.instance.database; final id=_uuid.v4();
    await db.transaction((txn) async { if((await txn.query('construction_projects',where:'id = ?',whereArgs:[projectId],limit:1)).isEmpty) throw StateError('Project not found.');
      await txn.insert('construction_tasks',{'id':id,'projectId':projectId,'title':title.trim(),'assignedTo':assignedTo,'status':'todo','cost':cost,'dueDate':dueDate});
      await txn.rawUpdate('UPDATE construction_projects SET spent = spent + ? WHERE id = ?',[cost,projectId]); }); return id;
  }
  Future<String> addPublicServiceCase({required String caseNumber, required String applicantName, required String serviceType, required double fee, String? notes}) async {
    if(caseNumber.trim().isEmpty || applicantName.trim().isEmpty || serviceType.trim().isEmpty || fee<0) throw ArgumentError('Invalid public service case.'); final id=_uuid.v4();
    await (await DBService.instance.database).insert('public_service_cases',{'id':id,'caseNumber':caseNumber.trim(),'applicantName':applicantName.trim(),'serviceType':serviceType.trim(),'openedAt':DateTime.now().toIso8601String(),'status':'open','fee':fee,'notes':notes}); return id;
  }

}
