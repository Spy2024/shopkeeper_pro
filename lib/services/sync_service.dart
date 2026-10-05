import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'db_service.dart';

class SyncService {
  SyncService._internal();
  static final SyncService instance = SyncService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Connectivity _connectivity = Connectivity();
  bool _isOnline = true;
  bool _isSyncing = false;

  bool get isOnline => _isOnline;
  bool get isSyncing => _isSyncing;

  Future<void> init(String userId) async {
    final initial = await _connectivity.checkConnectivity();
    _isOnline = initial != ConnectivityResult.none;
    _connectivity.onConnectivityChanged.listen((result) {
      _isOnline = result != ConnectivityResult.none;
      if (_isOnline) {
        _syncAll(userId);
      }
    });
  }

  CollectionReference<Map<String, dynamic>> _collection(
    String userId,
    String name,
  ) =>
      _firestore.collection('users').doc(userId).collection(name);

  Future<void> _writeBatch(
    String userId,
    String collectionName,
    List<Map<String, dynamic>> rows,
  ) async {
    for (var start = 0; start < rows.length; start += 400) {
      final end = start + 400 > rows.length ? rows.length : start + 400;
      final batch = _firestore.batch();
      for (final row in rows.sublist(start, end)) {
        final id = (row['cloudId'] ?? row['id'])?.toString();
        if (id == null || id.isEmpty) continue;
        batch.set(
          _collection(userId, collectionName).doc(id),
          row,
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    }
  }

  Future<void> _writeChildBatch(
    String userId,
    String parentCollection,
    String parentId,
    String childCollection,
    List<Map<String, dynamic>> rows,
  ) async {
    for (var start = 0; start < rows.length; start += 400) {
      final end = start + 400 > rows.length ? rows.length : start + 400;
      final batch = _firestore.batch();
      final parent = _collection(userId, parentCollection).doc(parentId);
      for (final row in rows.sublist(start, end)) {
        final id = (row['cloudId'] ?? row['id'])?.toString();
        if (id == null || id.isEmpty) continue;
        batch.set(
          parent.collection(childCollection).doc(id),
          row,
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    }
  }

  Future<void> _syncAll(String userId) async {
    if (_isSyncing || !_isOnline) return;
    _isSyncing = true;
    try {
      final db = await DBService.instance.database;

      final shopRows = await db.query('shop', limit: 1);
      if (shopRows.isNotEmpty) {
        await _collection(userId, 'shop').doc('profile').set(
              Map<String, dynamic>.from(shopRows.first),
              SetOptions(merge: true),
            );
      }

      final products = (await db.query('products'))
          .map((r) => Map<String, dynamic>.from(r))
          .toList();
      await _writeBatch(userId, 'products', products);

      final bills = (await db.query('bills'))
          .map((r) => Map<String, dynamic>.from(r))
          .toList();
      await _writeBatch(userId, 'bills', bills);
      for (final bill in bills) {
        final items = (await db.query(
          'bill_items',
          where: 'billId = ?',
          whereArgs: [bill['id']],
        ))
            .map((r) => Map<String, dynamic>.from(r))
            .toList();
        await _writeChildBatch(
          userId,
          'bills',
          bill['id'].toString(),
          'items',
          items,
        );
      }

      final suppliers = (await db.query('suppliers'))
          .map((r) => Map<String, dynamic>.from(r))
          .toList();
      await _writeBatch(userId, 'suppliers', suppliers);

      final orders = (await db.query('supplier_orders'))
          .map((r) => Map<String, dynamic>.from(r))
          .toList();
      await _writeBatch(userId, 'supplier_orders', orders);
      for (final order in orders) {
        final items = (await db.query(
          'supplier_order_items',
          where: 'orderId = ?',
          whereArgs: [order['id']],
        ))
            .map((r) => Map<String, dynamic>.from(r))
            .toList();
        await _writeChildBatch(
          userId,
          'supplier_orders',
          order['id'].toString(),
          'items',
          items,
        );
      }

      final sales = (await db.query('daily_sales'))
          .map((r) => Map<String, dynamic>.from(r))
          .toList();
      await _writeBatch(userId, 'sales', sales);

      final expenses = (await db.query('expenses'))
          .map((r) => Map<String, dynamic>.from(r))
          .toList();
      await _writeBatch(userId, 'expenses', expenses);
    } catch (e) {
      debugPrint('[SyncService] push error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> syncFromCloud(String userId) async {
    if (_isSyncing || !_isOnline) return;
    _isSyncing = true;
    try {
      final db = await DBService.instance.database;

      final shop = await _collection(userId, 'shop').doc('profile').get();
      if (shop.exists && shop.data() != null) {
        await db.insert(
          'shop',
          Map<String, dynamic>.from(shop.data()!),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      final products = await _collection(userId, 'products').get();
      for (final doc in products.docs) {
        await db.insert(
          'products',
          Map<String, dynamic>.from(doc.data()),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      final bills = await _collection(userId, 'bills').get();
      for (final doc in bills.docs) {
        final bill = Map<String, dynamic>.from(doc.data());
        await db.insert('bills', bill, conflictAlgorithm: ConflictAlgorithm.replace);
        final items = await doc.reference.collection('items').get();
        await db.delete('bill_items', where: 'billId = ?', whereArgs: [bill['id']]);
        for (final item in items.docs) {
          final data = Map<String, dynamic>.from(item.data());
          data['cloudId'] = item.id;
          await db.insert('bill_items', data, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }

      final suppliers = await _collection(userId, 'suppliers').get();
      for (final doc in suppliers.docs) {
        await db.insert(
          'suppliers',
          Map<String, dynamic>.from(doc.data()),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      final orders = await _collection(userId, 'supplier_orders').get();
      for (final doc in orders.docs) {
        final order = Map<String, dynamic>.from(doc.data());
        await db.insert(
          'supplier_orders',
          order,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        final items = await doc.reference.collection('items').get();
        await db.delete('supplier_order_items', where: 'orderId = ?', whereArgs: [order['id']]);
        for (final item in items.docs) {
          final data = Map<String, dynamic>.from(item.data());
          data['cloudId'] = item.id;
          await db.insert(
            'supplier_order_items',
            data,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }

      final sales = await _collection(userId, 'sales').get();
      for (final doc in sales.docs) {
        await db.insert(
          'daily_sales',
          Map<String, dynamic>.from(doc.data()),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      final expenses = await _collection(userId, 'expenses').get();
      for (final doc in expenses.docs) {
        await db.insert(
          'expenses',
          Map<String, dynamic>.from(doc.data()),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    } catch (e) {
      debugPrint('[SyncService] pull error: $e');
    } finally {
      _isSyncing = false;
    }
  }
}
