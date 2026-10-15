import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'db_service.dart';

/// Transaction-safe primitives for branch stock, cash, customer balances and
/// split tender. Global product stock is the total shop quantity; branch_stock
/// tracks its allocation across branches. Checkout decrements both atomically.
class BranchAccountingService {
  BranchAccountingService._();
  static final BranchAccountingService instance = BranchAccountingService._();

  final Uuid _uuid = const Uuid();

  Future<Database> get _database => DBService.instance.database;

  void _positiveFinite(double amount, String field, {bool allowZero = false}) {
    if (!amount.isFinite || (allowZero ? amount < 0 : amount <= 0)) {
      throw ArgumentError.value(amount, field, allowZero
          ? 'Must be finite and non-negative.'
          : 'Must be finite and greater than zero.');
    }
  }

  Future<int> branchStock(String branchId, String productId) async {
    final db = await _database;
    final rows = await db.query(
      'branch_stock',
      columns: ['quantity'],
      where: 'branchId = ? AND productId = ?',
      whereArgs: [branchId, productId],
      limit: 1,
    );
    return rows.isEmpty ? 0 : (rows.first['quantity'] as num).toInt();
  }

  Future<void> setBranchStock({
    required String branchId,
    required String productId,
    required int quantity,
    String note = 'Stock adjustment',
  }) async {
    final cleanBranchId = branchId.trim();
    final cleanProductId = productId.trim();
    if (cleanBranchId.isEmpty || cleanProductId.isEmpty) {
      throw ArgumentError('Branch and product are required.');
    }
    if (quantity < 0) throw ArgumentError.value(quantity, 'quantity', 'Cannot be negative.');
    final db = await _database;
    await db.transaction((txn) async {
      final branchRows = await txn.query(
        'branches',
        columns: ['id', 'isActive'],
        where: 'id = ?',
        whereArgs: [cleanBranchId],
        limit: 1,
      );
      if (branchRows.isEmpty || (branchRows.single['isActive'] as num?)?.toInt() != 1) {
        throw StateError('Selected branch does not exist or is inactive.');
      }
      final productRows = await txn.query(
        'products',
        columns: ['stockQuantity'],
        where: 'id = ?',
        whereArgs: [cleanProductId],
        limit: 1,
      );
      if (productRows.isEmpty) throw StateError('Selected product does not exist.');
      final totalStock = (productRows.single['stockQuantity'] as num).toInt();
      final otherRows = await txn.rawQuery(
        'SELECT COALESCE(SUM(quantity), 0) AS allocated FROM branch_stock '
        'WHERE productId = ? AND branchId != ?',
        [cleanProductId, cleanBranchId],
      );
      final allocatedElsewhere = (otherRows.single['allocated'] as num).toInt();
      final availableForBranch = (totalStock - allocatedElsewhere).clamp(0, totalStock).toInt();
      if (quantity > availableForBranch) {
        throw StateError(
          'Only $availableForBranch unit(s) are available to allocate to this branch.',
        );
      }
      await txn.insert('branch_stock', {
        'branchId': cleanBranchId,
        'productId': cleanProductId,
        'quantity': quantity,
        'updatedAt': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      // Global stock is the total across all branches plus unallocated stock.
      // Allocation changes only the branch breakdown, not total inventory.
    });
  }

  Future<void> transferStock({
    required String fromBranchId,
    required String toBranchId,
    required String productId,
    required int quantity,
    String? note,
  }) async {
    final cleanFromBranchId = fromBranchId.trim();
    final cleanToBranchId = toBranchId.trim();
    final cleanProductId = productId.trim();
    if (cleanFromBranchId.isEmpty || cleanToBranchId.isEmpty || cleanProductId.isEmpty) {
      throw ArgumentError('Source branch, destination branch, and product are required.');
    }
    if (cleanFromBranchId == cleanToBranchId) {
      throw ArgumentError('Source and destination branches must be different.');
    }
    if (quantity <= 0) throw ArgumentError.value(quantity, 'quantity', 'Must be positive.');
    final db = await _database;
    await db.transaction((txn) async {
      for (final branchId in [cleanFromBranchId, cleanToBranchId]) {
        final branchRows = await txn.query(
          'branches',
          columns: ['id', 'isActive'],
          where: 'id = ?',
          whereArgs: [branchId],
          limit: 1,
        );
        if (branchRows.isEmpty || (branchRows.single['isActive'] as num?)?.toInt() != 1) {
          throw StateError('Both source and destination branches must exist and be active.');
        }
      }
      final productRows = await txn.query(
        'products',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [cleanProductId],
        limit: 1,
      );
      if (productRows.isEmpty) throw StateError('Selected product does not exist.');
      final source = await txn.query(
        'branch_stock',
        columns: ['quantity'],
        where: 'branchId = ? AND productId = ?',
        whereArgs: [cleanFromBranchId, cleanProductId],
        limit: 1,
      );
      final available = source.isEmpty ? 0 : (source.first['quantity'] as num).toInt();
      if (available < quantity) {
        throw StateError('Insufficient branch stock: available $available, requested $quantity.');
      }
      final now = DateTime.now().toIso8601String();
      await txn.update(
        'branch_stock',
        {'quantity': available - quantity, 'updatedAt': now},
        where: 'branchId = ? AND productId = ?',
        whereArgs: [cleanFromBranchId, cleanProductId],
      );
      final target = await txn.query(
        'branch_stock',
        columns: ['quantity'],
        where: 'branchId = ? AND productId = ?',
        whereArgs: [cleanToBranchId, cleanProductId],
        limit: 1,
      );
      final targetQuantity = target.isEmpty ? 0 : (target.first['quantity'] as num).toInt();
      await txn.insert('branch_stock', {
        'branchId': cleanToBranchId,
        'productId': cleanProductId,
        'quantity': targetQuantity + quantity,
        'updatedAt': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('stock_transfers', {
        'id': _uuid.v4(),
        'fromBranchId': cleanFromBranchId,
        'toBranchId': cleanToBranchId,
        'productId': cleanProductId,
        'quantity': quantity,
        'status': 'completed',
        'createdAt': now,
        'note': note?.trim(),
      });
    });
  }

  Future<void> recordCashMovement({
    required String branchId,
    required String type,
    required double amount,
    String? referenceId,
    String? note,
    DateTime? date,
  }) async {
    const allowed = {
      'opening', 'cash_in', 'cash_out', 'sale', 'refund',
      'expense', 'transfer_in', 'transfer_out', 'adjustment',
    };
    if (!allowed.contains(type)) throw ArgumentError.value(type, 'type', 'Unsupported cash movement.');
    _positiveFinite(amount, 'amount', allowZero: true);
    final db = await _database;
    await db.insert('branch_cash_transactions', {
      'id': _uuid.v4(),
      'branchId': branchId,
      'type': type,
      'amount': amount,
      'date': (date ?? DateTime.now()).toIso8601String(),
      'referenceId': referenceId,
      'note': note?.trim(),
    });
  }

  Future<void> recordCustomerLedgerEntry({
    required String customerId,
    required String type,
    required double amount,
    String? referenceId,
    String? note,
    DateTime? date,
  }) async {
    const allowed = {'opening', 'sale_due', 'payment', 'refund', 'adjustment'};
    if (!allowed.contains(type)) throw ArgumentError.value(type, 'type', 'Unsupported ledger entry.');
    if (customerId.trim().isEmpty) throw ArgumentError('Customer is required.');
    _positiveFinite(amount, 'amount', allowZero: true);
    final db = await _database;
    await db.insert('customer_ledger', {
      'id': _uuid.v4(),
      'customerId': customerId,
      'type': type,
      'amount': amount,
      'date': (date ?? DateTime.now()).toIso8601String(),
      'referenceId': referenceId,
      'note': note?.trim(),
    });
  }

  /// Records a bill's split tender atomically. Credit is a payment method here;
  /// callers should create a customer ledger sale_due entry for the credit
  /// portion in the same business workflow.
  Future<void> recordPaymentAllocations({
    required String billId,
    required List<PaymentAllocationInput> allocations,
    required double billTotal,
  }) async {
    if (billId.trim().isEmpty) throw ArgumentError('Bill ID is required.');
    _positiveFinite(billTotal, 'billTotal', allowZero: true);
    if (allocations.isEmpty) throw ArgumentError('At least one payment allocation is required.');
    const allowedMethods = {'cash', 'card', 'bank', 'wallet', 'credit', 'other'};
    for (final item in allocations) {
      if (!allowedMethods.contains(item.method)) {
        throw ArgumentError.value(item.method, 'method', 'Unsupported payment method.');
      }
      _positiveFinite(item.amount, 'payment amount', allowZero: true);
    }
    final total = allocations.fold<double>(0, (sum, item) => sum + item.amount);
    if ((total - billTotal).abs() > 0.005) {
      throw ArgumentError('Payment allocations must equal the bill total.');
    }
    final db = await _database;
    await db.transaction((txn) async {
      final bill = await txn.query('bills', columns: ['id'], where: 'id = ?', whereArgs: [billId], limit: 1);
      if (bill.isEmpty) throw StateError('Bill was not found.');
      await txn.delete('payment_allocations', where: 'billId = ?', whereArgs: [billId]);
      final now = DateTime.now().toIso8601String();
      for (final allocation in allocations) {
        await txn.insert('payment_allocations', {
          'id': _uuid.v4(),
          'billId': billId,
          'method': allocation.method,
          'amount': allocation.amount,
          'reference': allocation.reference?.trim(),
          'createdAt': now,
        });
      }
    });
  }

  Future<double> customerBalance(String customerId) async {
    final db = await _database;
    final rows = await db.query(
      'customer_ledger',
      columns: ['type', 'amount'],
      where: 'customerId = ?',
      whereArgs: [customerId],
    );
    var balance = 0.0;
    for (final row in rows) {
      final amount = (row['amount'] as num).toDouble();
      switch (row['type']) {
        case 'opening':
        case 'sale_due':
          balance += amount;
          break;
        case 'payment':
        case 'refund':
          balance -= amount;
          break;
        case 'adjustment':
          break;
      }
    }
    return balance;
  }
}

class PaymentAllocationInput {
  final String method;
  final double amount;
  final String? reference;

  const PaymentAllocationInput({
    required this.method,
    required this.amount,
    this.reference,
  }) : assert(method == 'cash' || method == 'card' || method == 'bank' ||
            method == 'wallet' || method == 'credit' || method == 'other');
}