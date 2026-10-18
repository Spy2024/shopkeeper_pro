import 'package:sqflite/sqflite.dart';
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
  final int quantity;
  final double unitPrice;

  const ReturnLine({
    this.productId,
    required this.productName,
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
    if (!{'credit', 'payment', 'adjustment'}.contains(type)) {
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
      'type': type,
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
      for (final item in items) {
        final soldRows = await txn.rawQuery(
          'SELECT COALESCE(SUM(quantity), 0) AS qty FROM bill_items WHERE billId = ? AND productName = ?',
          [billId, item.productName],
        );
        final sold = (soldRows.first['qty'] as num).toInt();
        final returnedRows = await txn.rawQuery(
          'SELECT COALESCE(SUM(ri.quantity), 0) AS qty FROM return_items ri JOIN returns r ON r.id = ri.returnId WHERE r.billId = ? AND ri.productName = ?',
          [billId, item.productName],
        );
        final alreadyReturned = (returnedRows.first['qty'] as num).toInt();
        if (item.quantity + alreadyReturned > sold) {
          throw StateError('Return quantity exceeds remaining sold quantity for ${item.productName}.');
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
          'quantity': item.quantity,
          'unitPrice': item.unitPrice,
        });
        final products = item.productId != null
            ? await txn.query('products', where: 'id = ?', whereArgs: [item.productId], limit: 1)
            : await txn.query('products', where: 'name = ?', whereArgs: [item.productName], limit: 1);
        if (products.isNotEmpty) {
          final product = products.first;
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
          'type': 'payment',
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
    await db.insert('branches', {'id': id, 'name': name.trim(), 'address': address, 'phone': phone});
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
        await txn.insert('branch_stock', {'id': _uuid.v4(), 'branchId': branchId, 'productId': productId, 'quantity': quantity});
      } else {
        await txn.update('branch_stock', {'quantity': quantity},
            where: 'id = ?', whereArgs: [rows.first['id']]);
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
  }) async {
    final normalizedImei = imei.replaceAll(RegExp(r'\s+'), '');
    if (!RegExp(r'^\d{15}$').hasMatch(normalizedImei)) {
      throw ArgumentError('IMEI must contain exactly 15 digits.');
    }
    final id = _uuid.v4();
    final db = await DBService.instance.database;
    await db.insert('mobile_devices', {
      'id': id, 'productId': productId, 'imei': normalizedImei,
      'serialNumber': serialNumber, 'status': 'in_stock',
      'purchasePrice': purchasePrice, 'salePrice': salePrice, 'billId': null,
    });
    return id;
  }

  Future<void> markMobileDeviceSold({required String imei, required String billId}) async {
    final db = await DBService.instance.database;
    await db.transaction((txn) async {
      final devices = await txn.query('mobile_devices', where: 'imei = ?', whereArgs: [imei], limit: 1);
      final bill = await txn.query('bills', where: 'id = ?', whereArgs: [billId], limit: 1);
      if (devices.isEmpty || bill.isEmpty) throw StateError('IMEI device or bill not found.');
      if (devices.first['status'] != 'in_stock') throw StateError('This IMEI device is not available for sale.');
      await txn.update('mobile_devices', {'status': 'sold', 'billId': billId},
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

  Future<String> createRestaurantOrder({String? tableId, required double total}) async {
    if (total < 0) throw ArgumentError('Order total cannot be negative.');
    final db = await DBService.instance.database;
    await db.transaction((txn) async {
      if (tableId != null) {
        final tables = await txn.query('restaurant_tables',
            where: 'id = ?', whereArgs: [tableId], limit: 1);
        if (tables.isEmpty) throw StateError('Restaurant table not found.');
        if (tables.first['status'] != 'available') throw StateError('Restaurant table is already occupied.');
        await txn.update('restaurant_tables', {'status': 'occupied'},
            where: 'id = ?', whereArgs: [tableId]);
      }
    });
    final id = _uuid.v4();
    await db.insert('restaurant_orders', {
      'id': id, 'tableId': tableId, 'status': 'open',
      'total': total, 'createdAt': DateTime.now().toIso8601String(),
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
    await db.insert('cargo_jobs', {
      'id': id, 'routeId': routeId, 'customerName': customerName.trim(),
      'loadDescription': loadDescription, 'weight': weight,
      'freightAmount': freightAmount, 'status': 'created',
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

}
