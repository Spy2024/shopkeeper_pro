import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'db_service.dart';
import 'sync_queue_service.dart';

class SyncService {
  SyncService._internal();
  static final SyncService instance = SyncService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Connectivity _connectivity = Connectivity();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Future<void>? _syncInFlight;
  bool _isOnline = false;
  bool _isSyncing = false;

  bool get isOnline => _isOnline;
  bool get isSyncing => _isSyncing;

  static const Map<String, String> _collections = {
    'products': 'products',
    'bills': 'bills',
    'suppliers': 'suppliers',
    'supplier_orders': 'supplier_orders',
    'daily_sales': 'sales',
    'expenses': 'expenses',
  };

  Future<void> init(String userId) async {
    final connectivity = await _connectivity.checkConnectivity();
    _isOnline = !connectivity.contains(ConnectivityResult.none);

    await _connectivitySubscription?.cancel();
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((result) {
      _isOnline = !result.contains(ConnectivityResult.none);
      if (_isOnline) {
        unawaited(syncNow(userId));
      }
    });

    if (_isOnline) {
      await syncNow(userId);
    }
  }

  Future<void> dispose() async {
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
  }

  Future<void> syncNow(String userId) {
    final existing = _syncInFlight;
    if (existing != null) return existing;

    final future = _runSync(userId);
    _syncInFlight = future;
    return future.whenComplete(() {
      if (identical(_syncInFlight, future)) {
        _syncInFlight = null;
      }
    });
  }

  /// Kept as a compatibility entry point. Concurrent calls are coalesced.
  Future<void> syncFromCloud(String userId) {
    return _syncLocked(userId, pullOnly: true);
  }

  Future<void> _syncLocked(String userId, {required bool pullOnly}) {
    final existing = _syncInFlight;
    if (existing != null) return existing;

    final future = _runSync(userId, pullOnly: pullOnly);
    _syncInFlight = future;
    return future.whenComplete(() {
      if (identical(_syncInFlight, future)) {
        _syncInFlight = null;
      }
    });
  }

  Future<void> _runSync(String userId, {bool pullOnly = false}) async {
    if (!_isOnline) return;
    _isSyncing = true;
    try {
      if (!pullOnly) {
        await SyncQueueService.instance.syncPendingOperations(userId);
        await _pushLocalSnapshot(userId);
      }
      await _pullCloudSnapshot(userId);
    } catch (e, st) {
      debugPrint('[SyncService] Sync error: $e');
      debugPrintStack(stackTrace: st);
    } finally {
      _isSyncing = false;
    }
  }

  Future<DocumentReference<Map<String, dynamic>>> _refFor(
    String userId,
    String tableName,
    String documentId,
  ) async {
    if (tableName == 'shop') {
      return _firestore.collection('users').doc(userId).collection('shop').doc('profile');
    }
    final collection = _collections[tableName];
    if (collection == null) {
      throw StateError('Unsupported sync table: $tableName');
    }
    return _firestore.collection('users').doc(userId).collection(collection).doc(documentId);
  }

  Future<int> _localTimestamp(Database db, String tableName, String documentId) async {
    final rows = await db.query(
      'sync_metadata',
      columns: ['updatedAt'],
      where: 'tableName = ? AND documentId = ?',
      whereArgs: [tableName, documentId],
      limit: 1,
    );
    return rows.isEmpty ? 0 : (rows.first['updatedAt'] as num).toInt();
  }

  int _cloudTimestamp(Map<String, dynamic>? data) {
    final value = data?['_syncUpdatedAt'];
    if (value is num) return value.toInt();
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    return 0;
  }

  Map<String, dynamic> _cleanCloudData(Map<String, dynamic> data) {
    final clean = Map<String, dynamic>.from(data)
      ..remove('_syncUpdatedAt')
      ..remove('_deleted');
    return clean;
  }

  Future<void> _pushLocalSnapshot(String userId) async {
    final db = await DBService.instance.database;

    final shopRows = await db.query('shop', limit: 1);
    if (shopRows.isNotEmpty) {
      await _pushRow(userId, 'shop', 'profile', shopRows.first, db);
    }

    for (final entry in _collections.entries) {
      final table = entry.key;
      final rows = await db.query(table);
      for (final row in rows) {
        final documentId = (row['id'] ?? '').toString();
        if (documentId.isEmpty) continue;

        Map<String, dynamic> payload = Map<String, dynamic>.from(row);

        if (table == 'bills') {
          final items = await db.query('bill_items', where: 'billId = ?', whereArgs: [documentId]);
          payload['items'] = items.map((item) => Map<String, dynamic>.from(item)).toList();
        } else if (table == 'supplier_orders') {
          final items = await db.query(
            'supplier_order_items',
            where: 'orderId = ?',
            whereArgs: [documentId],
          );
          payload['items'] = items.map(Map<String, dynamic>.from).toList();
        }

        await _pushRow(userId, table, documentId, payload, db);
      }
    }
  }

  Future<void> _pushRow(
    String userId,
    String tableName,
    String documentId,
    Map<String, dynamic> payload,
    Database db,
  ) async {
    final ref = await _refFor(userId, tableName, documentId);
    final snapshot = await ref.get();
    final cloudTimestamp = _cloudTimestamp(snapshot.data());
    final localTimestamp = await _localTimestamp(db, tableName, documentId);

    if (snapshot.exists && cloudTimestamp > localTimestamp) {
      return;
    }

    final timestamp = localTimestamp > 0
        ? localTimestamp
        : DateTime.now().millisecondsSinceEpoch;

    await ref.set({
      ...payload,
      '_deleted': false,
      '_syncUpdatedAt': timestamp,
    }, SetOptions(merge: true));

    await db.insert(
      'sync_metadata',
      {'tableName': tableName, 'documentId': documentId, 'updatedAt': timestamp},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _pullCloudSnapshot(String userId) async {
    final db = await DBService.instance.database;

    final shopRef = await _refFor(userId, 'shop', 'profile');
    final shopSnap = await shopRef.get();
    if (shopSnap.exists && shopSnap.data() != null) {
      await _applyCloudDocument(db, 'shop', 'profile', shopSnap.data()!);
    }

    for (final entry in _collections.entries) {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection(entry.value)
          .get();

      for (final doc in snapshot.docs) {
        await _applyCloudDocument(db, entry.key, doc.id, doc.data());
      }
    }
  }

  Future<void> _applyCloudDocument(
    Database db,
    String tableName,
    String documentId,
    Map<String, dynamic> cloudData,
  ) async {
    final cloudTimestamp = _cloudTimestamp(cloudData);
    final localTimestamp = await _localTimestamp(db, tableName, documentId);
    if (cloudTimestamp < localTimestamp) return;

    final deleted = cloudData['_deleted'] == true;
    if (deleted) {
      await _deleteLocalDocument(db, tableName, documentId);
    } else {
      final clean = _cleanCloudData(cloudData);
      await _upsertLocalDocument(db, tableName, documentId, clean);
      if (tableName == 'bills' && clean['items'] is List) {
        await _replaceBillItems(db, documentId, List<dynamic>.from(clean['items'] as List));
      }
      if (tableName == 'supplier_orders' && clean['items'] is List) {
        await _replaceSupplierOrderItems(
          db,
          documentId,
          List<dynamic>.from(clean['items'] as List),
        );
      }
    }

    await db.insert(
      'sync_metadata',
      {'tableName': tableName, 'documentId': documentId, 'updatedAt': cloudTimestamp},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _upsertLocalDocument(
    Database db,
    String tableName,
    String documentId,
    Map<String, dynamic> data,
  ) async {
    final clean = Map<String, dynamic>.from(data)
      ..remove('items');

    if (tableName == 'shop') {
      clean['id'] = clean['id'] ?? documentId;
      await db.insert('shop', clean, conflictAlgorithm: ConflictAlgorithm.replace);
      return;
    }

    clean['id'] = clean['id'] ?? documentId;
    await db.insert(tableName, clean, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _deleteLocalDocument(
    Database db,
    String tableName,
    String documentId,
  ) async {
    if (tableName == 'shop') {
      await db.delete('shop', where: 'id = ?', whereArgs: [documentId]);
      return;
    }

    await db.transaction((txn) async {
      if (tableName == 'bills') {
        await txn.delete('bill_items', where: 'billId = ?', whereArgs: [documentId]);
      }
      if (tableName == 'supplier_orders') {
        await txn.delete(
          'supplier_order_items',
          where: 'orderId = ?',
          whereArgs: [documentId],
        );
      }
      await txn.delete(tableName, where: 'id = ?', whereArgs: [documentId]);
    });
  }

  Future<void> _replaceBillItems(
    Database db,
    String billId,
    List<dynamic> rawItems,
  ) async {
    await db.transaction((txn) async {
      await txn.delete('bill_items', where: 'billId = ?', whereArgs: [billId]);
      for (var index = 0; index < rawItems.length; index++) {
        final item = Map<String, dynamic>.from(rawItems[index] as Map);
        item.remove('id');
        item['billId'] = billId;
        await txn.insert('bill_items', item);
      }
    });
  }

  Future<void> _replaceSupplierOrderItems(
    Database db,
    String orderId,
    List<dynamic> rawItems,
  ) async {
    await db.transaction((txn) async {
      await txn.delete('supplier_order_items', where: 'orderId = ?', whereArgs: [orderId]);
      for (final raw in rawItems) {
        final item = Map<String, dynamic>.from(raw as Map);
        item.remove('id');
        item['orderId'] = orderId;
        await txn.insert('supplier_order_items', item);
      }
    });
  }
}
