import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/customer.dart';
import '../services/db_service.dart';
import '../services/sync_queue_service.dart';

class CustomerProvider extends ChangeNotifier {
  final List<Customer> _customers = [];
  final Uuid _uuid = const Uuid();

  List<Customer> get customers => List.unmodifiable(_customers);

  List<Customer> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return customers;
    return _customers.where((c) =>
      c.name.toLowerCase().contains(q) ||
      (c.phone?.toLowerCase().contains(q) ?? false) ||
      (c.email?.toLowerCase().contains(q) ?? false)
    ).toList(growable: false);
  }

  Future<void> load() async {
    final db = await DBService.instance.database;
    final rows = await db.query('customers', orderBy: 'name COLLATE NOCASE ASC');
    _customers..clear()..addAll(rows.map(Customer.fromMap));
    notifyListeners();
  }

  Future<Customer> add({required String name, String? phone, String? email, String? notes}) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('Customer name is required.');
    final cleanPhone = phone?.trim();
    final cleanEmail = email?.trim();
    if (cleanEmail != null && cleanEmail.isNotEmpty &&
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(cleanEmail)) {
      throw ArgumentError('Enter a valid email address.');
    }
    final customer = Customer(
      id: _uuid.v4(), name: cleanName,
      phone: cleanPhone?.isEmpty == true ? null : cleanPhone,
      email: cleanEmail?.isEmpty == true ? null : cleanEmail,
      notes: notes?.trim().isEmpty == true ? null : notes?.trim(),
      createdAt: DateTime.now(),
    );
    final db = await DBService.instance.database;
    await db.insert('customers', customer.toMap());
    _customers.add(customer);
    _customers.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    try {
      await SyncQueueService.instance.queueOperation(operation: 'create', tableName: 'customers',
        documentId: customer.id, data: customer.toMap());
    } catch (_) {
      // Local-first: preserve the local record while cloud sync is unavailable.
    }
    notifyListeners();
    return customer;
  }

  Future<void> updateCustomer(Customer customer) async {
    final db = await DBService.instance.database;
    final changed = await db.update('customers', customer.toMap(), where: 'id = ?', whereArgs: [customer.id]);
    if (changed == 0) throw StateError('Customer no longer exists.');
    final index = _customers.indexWhere((c) => c.id == customer.id);
    if (index >= 0) _customers[index] = customer;
    _customers.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    try {
      await SyncQueueService.instance.queueOperation(operation: 'update', tableName: 'customers',
        documentId: customer.id, data: customer.toMap());
    } catch (_) {
      // Local edit remains available offline.
    }
    notifyListeners();
  }

  Future<void> delete(String id) async {
    if (id.trim().isEmpty) throw ArgumentError('Customer id is required.');
    final db = await DBService.instance.database;
    final exists = await db.query('customers', columns: ['id'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (exists.isEmpty) return;

    // Persist the tombstone before deleting locally. Otherwise, a cloud record
    // could be downloaded again on the next sync and resurrect the deleted customer.
    await SyncQueueService.instance.queueOperation(
      operation: 'delete', tableName: 'customers', documentId: id, data: const {},
    );
    await db.delete('customers', where: 'id = ?', whereArgs: [id]);
    _customers.removeWhere((c) => c.id == id);
    notifyListeners();
  }
}
