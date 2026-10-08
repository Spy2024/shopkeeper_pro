import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'db_service.dart';
import 'sync_queue_service.dart';
import 'backup_restore_service.dart';

class SyncService {
  SyncService._internal();
  static final SyncService instance = SyncService._internal();
  FirebaseFirestore? _firestore;
  FirebaseFirestore get _dbFirestore => _firestore ??= FirebaseFirestore.instance;
  final Connectivity _connectivity = Connectivity();
  bool _isOnline = false;
  bool _isSyncing = false;
  bool get isOnline => _isOnline;
  bool get isSyncing => _isSyncing;

  Future<void> init(String userId) async {
    if (userId.trim().isEmpty) return;
    final result = await _connectivity.checkConnectivity();
    _isOnline = _hasNetwork(result);
  }

  bool _hasNetwork(List<ConnectivityResult> result) => result.any((r) => r != ConnectivityResult.none);
  CollectionReference<Map<String, dynamic>> _collection(String userId, String name) =>
      _dbFirestore.collection('users').doc(userId).collection(name);

  Future<bool> _checkOnline() async {
    final result = await _connectivity.checkConnectivity();
    _isOnline = _hasNetwork(result);
    return _isOnline;
  }

  Future<void> syncNow(String userId) async {
    final authenticatedUid = FirebaseAuth.instance.currentUser?.uid;
    if (userId.trim().isEmpty || authenticatedUid != userId || _isSyncing || !await _checkOnline()) return;
    _isSyncing = true;
    try {
      await SyncQueueService.instance.syncPendingOperations(userId);
      await _pushLocal(userId);
      await syncFromCloud(userId, lockAlreadyHeld: true);
      try {
        await BackupRestoreService.instance.maybeCreateAutomaticCloudBackup(userId);
      } catch (e) {
        debugPrint('[SyncService] automatic cloud backup failed; it will retry on a later sync: $e');
      }
    } catch (e) {
      debugPrint('[SyncService] sync error: $e');
      rethrow;
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _writeBatch(String userId, String collectionName, List<Map<String, dynamic>> rows) async {
    for (var start = 0; start < rows.length; start += 400) {
      final end = ((start + 400) > rows.length) ? rows.length : start + 400;
      final batch = _dbFirestore.batch();
      for (final raw in rows.sublist(start, end)) {
        final row = Map<String, dynamic>.from(raw);
        final id = (row['cloudId'] ?? row['id'])?.toString();
        if (id == null || id.isEmpty) continue;
        row['updatedAt'] ??= FieldValue.serverTimestamp();
        batch.set(_collection(userId, collectionName).doc(id), row, SetOptions(merge: true));
      }
      await batch.commit();
    }
  }

  Future<void> _writeChildBatch(String userId, String parentCollection, String parentId, String childCollection, List<Map<String, dynamic>> rows) async {
    for (var start = 0; start < rows.length; start += 400) {
      final end = ((start + 400) > rows.length) ? rows.length : start + 400;
      final batch = _dbFirestore.batch();
      final parent = _collection(userId, parentCollection).doc(parentId);
      for (final raw in rows.sublist(start, end)) {
        final row = Map<String, dynamic>.from(raw);
        final id = (row['cloudId'] ?? row['id'])?.toString();
        if (id == null || id.isEmpty) continue;
        row['updatedAt'] ??= FieldValue.serverTimestamp();
        batch.set(parent.collection(childCollection).doc(id), row, SetOptions(merge: true));
      }
      await batch.commit();
    }
  }

  Future<void> _pushLocal(String userId) async {
    final db = await DBService.instance.database;
    final shopRows = await db.query('shop', limit: 1);
    if (shopRows.isNotEmpty) {
      await _collection(userId, 'shop').doc('profile').set({...Map<String, dynamic>.from(shopRows.first), 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    }
    await _writeBatch(userId, 'products', await _maps(db, 'products'));
    final bills = await _maps(db, 'bills');
    await _writeBatch(userId, 'bills', bills);
    for (final bill in bills) {
      await _writeChildBatch(userId, 'bills', bill['id'].toString(), 'items', await _maps(db, 'bill_items', where: 'billId = ?', args: [bill['id']]));
    }
    await _writeBatch(userId, 'suppliers', await _maps(db, 'suppliers'));
    await _writeBatch(userId, 'supplier_transactions', await _maps(db, 'supplier_transactions'));
    final orders = await _maps(db, 'supplier_orders');
    await _writeBatch(userId, 'supplier_orders', orders);
    for (final order in orders) {
      await _writeChildBatch(userId, 'supplier_orders', order['id'].toString(), 'items', await _maps(db, 'supplier_order_items', where: 'orderId = ?', args: [order['id']]));
    }
    await _writeBatch(userId, 'sales', await _maps(db, 'daily_sales'));
    await _writeBatch(userId, 'returns', await _maps(db, 'bill_returns'));
    await _writeBatch(userId, 'expenses', await _maps(db, 'expenses'));
  }

  Future<List<Map<String, dynamic>>> _maps(Database db, String table, {String? where, List<Object?>? args}) async {
    final rows = await db.query(table, where: where, whereArgs: args);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<bool> _hasPending(Database db, String documentId) async {
    final rows = await db.query('sync_queue', columns: ['id'], where: 'synced = 0 AND documentId = ?', whereArgs: [documentId], limit: 1);
    return rows.isNotEmpty;
  }

  Future<void> syncFromCloud(String userId, {bool lockAlreadyHeld = false}) async {
    final authenticatedUid = FirebaseAuth.instance.currentUser?.uid;
    if (userId.trim().isEmpty || authenticatedUid != userId || (!lockAlreadyHeld && _isSyncing) || !await _checkOnline()) return;
    final lockedHere = !lockAlreadyHeld;
    if (lockedHere) _isSyncing = true;
    try {
      final db = await DBService.instance.database;
      final shop = await _collection(userId, 'shop').doc('profile').get();
      if (shop.exists && shop.data() != null && !(await _hasPending(db, 'profile'))) {
        final data = Map<String, dynamic>.from(shop.data()!)..remove('updatedAt');
        await db.delete('shop');
        await db.insert('shop', data, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      final products = await _collection(userId, 'products').get();
      for (final doc in products.docs) {
        if (await _hasPending(db, doc.id)) continue;
        final data = Map<String, dynamic>.from(doc.data())..remove('updatedAt');
        await db.insert('products', data, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      final bills = await _collection(userId, 'bills').get();
      for (final doc in bills.docs) {
        if (await _hasPending(db, doc.id)) continue;
        final bill = Map<String, dynamic>.from(doc.data())..remove('updatedAt');
        await db.insert('bills', bill, conflictAlgorithm: ConflictAlgorithm.replace);
        final items = await doc.reference.collection('items').get();
        if (await _hasPending(db, doc.id)) continue;
        await db.delete('bill_items', where: 'billId = ?', whereArgs: [doc.id]);
        for (final item in items.docs) {
          final data = Map<String, dynamic>.from(item.data())..remove('updatedAt');
          data['cloudId'] = item.id;
          await db.insert('bill_items', data, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }

      final suppliers = await _collection(userId, 'suppliers').get();
      for (final doc in suppliers.docs) {
        if (await _hasPending(db, doc.id)) continue;
        final data = Map<String, dynamic>.from(doc.data())..remove('updatedAt');
        await db.insert('suppliers', data, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      final supplierTransactions = await _collection(userId, 'supplier_transactions').get();
      for (final doc in supplierTransactions.docs) {
        if (await _hasPending(db, doc.id)) continue;
        final data = Map<String, dynamic>.from(doc.data())..remove('updatedAt');
        await db.insert('supplier_transactions', data, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      final supplierOrders = await _collection(userId, 'supplier_orders').get();
      for (final doc in supplierOrders.docs) {
        if (await _hasPending(db, doc.id)) continue;
        final order = Map<String, dynamic>.from(doc.data())..remove('updatedAt');
        await db.insert('supplier_orders', order, conflictAlgorithm: ConflictAlgorithm.replace);
        final items = await doc.reference.collection('items').get();
        if (await _hasPending(db, doc.id)) continue;
        await db.delete('supplier_order_items', where: 'orderId = ?', whereArgs: [doc.id]);
        for (final item in items.docs) {
          final data = Map<String, dynamic>.from(item.data())..remove('updatedAt');
          data['cloudId'] = item.id;
          await db.insert('supplier_order_items', data, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }

      for (final collection in ['sales', 'expenses', 'returns']) {
        final snapshot = await _collection(userId, collection).get();
        for (final doc in snapshot.docs) {
          if (await _hasPending(db, doc.id)) continue;
          final data = Map<String, dynamic>.from(doc.data())..remove('updatedAt');
          final table = collection == 'sales'
              ? 'daily_sales'
              : collection == 'returns'
                  ? 'bill_returns'
                  : 'expenses';
          await db.insert(table, data, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    } finally {
      if (lockedHere) _isSyncing = false;
    }
  }
}
