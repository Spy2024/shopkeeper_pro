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

  /// Checks all non-destructive preconditions before a cloud backup restore
  /// replaces the local database. The destructive operation rechecks these
  /// conditions immediately before changing cloud data.
  Future<void> ensureCloudRestoreReady(String userId) async {
    if (userId.trim().isEmpty ||
        FirebaseAuth.instance.currentUser?.uid != userId ||
        DBService.instance.activeUserId != userId) {
      throw StateError('Sign in with the account that owns this data before restoring cloud records.');
    }
    if (_isSyncing) {
      throw StateError('Sync is already running. Wait for it to finish and retry restore.');
    }
    if (!await _checkOnline()) {
      throw StateError('An internet connection is required to restore and reconcile cloud data.');
    }
    // Connectivity checks are asynchronous; recheck the lock after awaiting.
    if (_isSyncing) {
      throw StateError('Sync started while preparing restore. Wait for it to finish and retry.');
    }
  }

  Future<void> syncNow(String userId) async {
    final authenticatedUid = FirebaseAuth.instance.currentUser?.uid;
    if (userId.trim().isEmpty ||
        authenticatedUid != userId ||
        DBService.instance.activeUserId != userId ||
        _isSyncing ||
        !await _checkOnline()) {
      return;
    }

    // A restored snapshot must be reconciled before ordinary bidirectional sync;
    // otherwise cloud-only records could be downloaded and resurrected.
    final db = await DBService.instance.database;
    final pendingRestore = await db.query(
      'sync_metadata',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['cloud_restore_pending'],
      limit: 1,
    );
    if (pendingRestore.isNotEmpty) {
      if (pendingRestore.first['value'] != userId) {
        throw StateError('Pending restore belongs to a different account; refusing to sync.');
      }
      await replaceCloudWithLocalSnapshot(userId);
    }
    if (_isSyncing) return;
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

  /// Replaces this account's managed cloud data with the current local
  /// snapshot. Use only for an explicit restore; normal sync must merge first
  /// so cloud-only records are not accidentally deleted.
  /// Retries a previously restored local snapshot when connectivity returns.
  /// Returns false when reconciliation is still pending because the device is offline.
  Future<bool> reconcilePendingRestoreIfOnline(String userId) async {
    if (userId.trim().isEmpty ||
        FirebaseAuth.instance.currentUser?.uid != userId ||
        DBService.instance.activeUserId != userId) {
      throw StateError('Sign in with the account that owns this data before syncing restored records.');
    }
    final db = await DBService.instance.database;
    final pending = await db.query(
      'sync_metadata',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['cloud_restore_pending'],
      limit: 1,
    );
    if (pending.isEmpty) return true;
    if (pending.first['value'] != userId) {
      throw StateError('Pending restore belongs to a different account; refusing to sync.');
    }
    if (!await _checkOnline()) return false;
    await replaceCloudWithLocalSnapshot(userId);
    return true;
  }

  Future<void> replaceCloudWithLocalSnapshot(String userId) async {
    await ensureCloudRestoreReady(userId);
    // Claim the lock before the first await in the destructive phase. If any
    // upload fails, stale records are not deleted and can be reconciled later.
    _isSyncing = true;
    try {
      final db = await DBService.instance.database;
      final shopRows = await db.query('shop', limit: 1);

      // Phase 1: upsert the complete local snapshot. Do not delete anything
      // until every local collection and child collection has been uploaded.
      await _pushLocal(userId);

      // Phase 2: remove only cloud records absent from the restored snapshot.
      // Reconcile child collections before deleting parent documents because
      // Firestore does not cascade parent deletes into subcollections.
      final bills = await _maps(db, 'bills');
      final orders = await _maps(db, 'supplier_orders');
      await _reconcileChildren(
        userId: userId,
        parentCollection: 'bills',
        childCollection: 'items',
        localParents: bills,
        localChildTable: 'bill_items',
        localParentKey: 'billId',
      );
      await _reconcileChildren(
        userId: userId,
        parentCollection: 'supplier_orders',
        childCollection: 'items',
        localParents: orders,
        localChildTable: 'supplier_order_items',
        localParentKey: 'orderId',
      );

      final tablesByCollection = <String, String>{
        'bills': 'bills',
        'supplier_orders': 'supplier_orders',
        'products': 'products',
        'branches': 'branches',
        'customers': 'customers',
        'suppliers': 'suppliers',
        'supplier_transactions': 'supplier_transactions',
        'sales': 'daily_sales',
        'returns': 'bill_returns',
        'expenses': 'expenses',
      };
      for (final entry in tablesByCollection.entries) {
        await _deleteCloudDocumentsMissingLocally(
          userId,
          entry.key,
          await _maps(db, entry.value),
        );
      }

      final shopRef = _collection(userId, 'shop').doc('profile');
      if (shopRows.isEmpty) {
        await shopRef.delete();
      }
      await db.delete(
        'sync_metadata',
        where: 'key = ? AND value = ?',
        whereArgs: ['cloud_restore_pending', userId],
      );
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _reconcileChildren({
    required String userId,
    required String parentCollection,
    required String childCollection,
    required List<Map<String, dynamic>> localParents,
    required String localChildTable,
    required String localParentKey,
  }) async {
    final db = await DBService.instance.database;
    final localParentsById = <String, Map<String, dynamic>>{
      for (final row in localParents)
        if (row['id'] != null) row['id'].toString(): row,
    };
    final cloudParents = await _collection(userId, parentCollection).get();
    for (final parent in cloudParents.docs) {
      final localParent = localParentsById[parent.id];
      final localChildren = localParent == null
          ? <Map<String, dynamic>>[]
          : await _maps(
              db,
              localChildTable,
              where: '$localParentKey = ?',
              args: [localParent['id']],
            );
      final keepIds = <String>{
        for (final row in localChildren)
          if ((row['cloudId'] ?? row['id']) != null)
            (row['cloudId'] ?? row['id']).toString(),
      };
      final cloudChildren = await parent.reference.collection(childCollection).get();
      final stale = cloudChildren.docs
          .where((doc) => !keepIds.contains(doc.id))
          .toList(growable: false);
      for (var start = 0; start < stale.length; start += 400) {
        final end = ((start + 400) > stale.length) ? stale.length : start + 400;
        final batch = _dbFirestore.batch();
        for (final child in stale.sublist(start, end)) {
          batch.delete(child.reference);
        }
        await batch.commit();
      }
    }
  }

  Future<void> _deleteCloudDocumentsMissingLocally(
    String userId,
    String collectionName,
    List<Map<String, dynamic>> localRows,
  ) async {
    final keepIds = <String>{
      for (final row in localRows)
        if ((row['cloudId'] ?? row['id']) != null &&
            (row['cloudId'] ?? row['id']).toString().isNotEmpty)
          (row['cloudId'] ?? row['id']).toString(),
    };
    final cloudRows = await _collection(userId, collectionName).get();
    final stale = cloudRows.docs
        .where((doc) => !keepIds.contains(doc.id))
        .toList(growable: false);
    for (var start = 0; start < stale.length; start += 400) {
      final end = ((start + 400) > stale.length) ? stale.length : start + 400;
      final batch = _dbFirestore.batch();
      for (final doc in stale.sublist(start, end)) {
        batch.delete(doc.reference);
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
    await _writeBatch(userId, 'branches', await _maps(db, 'branches'));
    await _writeBatch(userId, 'customers', await _maps(db, 'customers'));
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
    if (userId.trim().isEmpty || authenticatedUid != userId || DBService.instance.activeUserId != userId || (!lockAlreadyHeld && _isSyncing) || !await _checkOnline()) return;
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

      final branches = await _collection(userId, 'branches').get();
      for (final doc in branches.docs) {
        if (await _hasPending(db, doc.id)) continue;
        final data = Map<String, dynamic>.from(doc.data())..remove('updatedAt');
        await db.insert('branches', data, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      final customers = await _collection(userId, 'customers').get();
      for (final doc in customers.docs) {
        if (await _hasPending(db, doc.id)) continue;
        final data = Map<String, dynamic>.from(doc.data())..remove('updatedAt');
        await db.insert('customers', data, conflictAlgorithm: ConflictAlgorithm.replace);
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
