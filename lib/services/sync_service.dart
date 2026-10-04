import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'db_service.dart';

/// Multi-device sync service using Firebase Firestore.
/// Syncs local SQLite changes to cloud and vice versa.
/// Handles offline-first with sync queue.
class SyncService {
  SyncService._internal();
  static final SyncService instance = SyncService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Connectivity _connectivity = Connectivity();
  bool _isOnline = true;
  bool _isSyncing = false;

  bool get isOnline => _isOnline;
  bool get isSyncing => _isSyncing;

  /// Initialize sync service and monitor connectivity
  Future<void> init(String userId) async {
    _connectivity.onConnectivityChanged.listen((result) {
      _isOnline = !result.contains(ConnectivityResult.none);
      if (_isOnline) {
        debugPrint('[SyncService] Online detected, triggering sync');
        _syncAll(userId);
      }
    });
  }

  /// Sync all local data to Firebase (push)
  Future<void> _syncAll(String userId) async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final db = await DBService.instance.database;

      // Sync shop profile
      debugPrint('[SyncService] Syncing shop profile...');
      final shopRows = await db.query('shop', limit: 1);
      if (shopRows.isNotEmpty) {
        await _firestore
            .collection('users')
            .doc(userId)
            .collection('shop')
            .doc('profile')
            .set(shopRows.first as Map<String, dynamic>, SetOptions(merge: true));
      }

      // Sync products with batch
      debugPrint('[SyncService] Syncing products...');
      final products = await db.query('products');
      final productBatch = _firestore.batch();
      for (final product in products) {
        final ref = _firestore
            .collection('users')
            .doc(userId)
            .collection('products')
            .doc(product['id'] as String);
        productBatch.set(ref, product as Map<String, dynamic>, SetOptions(merge: true));
      }
      await productBatch.commit();
      debugPrint('[SyncService] Synced ${products.length} products');

      // Sync bills with batch
      debugPrint('[SyncService] Syncing bills...');
      final bills = await db.query('bills');
      final billBatch = _firestore.batch();
      for (final bill in bills) {
        final ref = _firestore
            .collection('users')
            .doc(userId)
            .collection('bills')
            .doc(bill['id'] as String);
        billBatch.set(ref, bill as Map<String, dynamic>, SetOptions(merge: true));
      }
      await billBatch.commit();
      debugPrint('[SyncService] Synced ${bills.length} bills');

      // Sync suppliers
      debugPrint('[SyncService] Syncing suppliers...');
      final suppliers = await db.query('suppliers');
      final supplierBatch = _firestore.batch();
      for (final supplier in suppliers) {
        final ref = _firestore
            .collection('users')
            .doc(userId)
            .collection('suppliers')
            .doc(supplier['id'] as String);
        supplierBatch.set(ref, supplier as Map<String, dynamic>, SetOptions(merge: true));
      }
      await supplierBatch.commit();
      debugPrint('[SyncService] Synced ${suppliers.length} suppliers');

      // Sync sales
      debugPrint('[SyncService] Syncing sales...');
      final sales = await db.query('daily_sales');
      final salesBatch = _firestore.batch();
      for (final sale in sales) {
        final ref = _firestore
            .collection('users')
            .doc(userId)
            .collection('sales')
            .doc(sale['id'] as String);
        salesBatch.set(ref, sale as Map<String, dynamic>, SetOptions(merge: true));
      }
      await salesBatch.commit();
      debugPrint('[SyncService] Synced ${sales.length} sales entries');

      // Sync expenses
      debugPrint('[SyncService] Syncing expenses...');
      final expenses = await db.query('expenses');
      final expenseBatch = _firestore.batch();
      for (final expense in expenses) {
        final ref = _firestore
            .collection('users')
            .doc(userId)
            .collection('expenses')
            .doc(expense['id'] as String);
        expenseBatch.set(ref, expense as Map<String, dynamic>, SetOptions(merge: true));
      }
      await expenseBatch.commit();
      debugPrint('[SyncService] Synced ${expenses.length} expenses');

      debugPrint('[SyncService] ✓ All data synced to cloud');
    } catch (e) {
      debugPrint('[SyncService] Sync error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Download cloud data and merge with local SQLite (pull)
  Future<void> syncFromCloud(String userId) async {
    if (_isSyncing || !_isOnline) return;
    _isSyncing = true;

    try {
      final db = await DBService.instance.database;

      // Sync shop
      debugPrint('[SyncService] Pulling shop from cloud...');
      final shopSnap = await _firestore
          .collection('users')
          .doc(userId)
          .collection('shop')
          .doc('profile')
          .get();
      if (shopSnap.exists) {
        await db.insert('shop', shopSnap.data()!,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }

      // Pull products
      debugPrint('[SyncService] Pulling products from cloud...');
      final productsSnap = await _firestore
          .collection('users')
          .doc(userId)
          .collection('products')
          .get();
      for (final doc in productsSnap.docs) {
        await db.insert('products', doc.data(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      debugPrint('[SyncService] Pulled ${productsSnap.docs.length} products');

      // Pull bills
      debugPrint('[SyncService] Pulling bills from cloud...');
      final billsSnap = await _firestore
          .collection('users')
          .doc(userId)
          .collection('bills')
          .get();
      for (final doc in billsSnap.docs) {
        await db.insert('bills', doc.data(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      debugPrint('[SyncService] Pulled ${billsSnap.docs.length} bills');

      // Pull suppliers
      debugPrint('[SyncService] Pulling suppliers from cloud...');
      final suppliersSnap = await _firestore
          .collection('users')
          .doc(userId)
          .collection('suppliers')
          .get();
      for (final doc in suppliersSnap.docs) {
        await db.insert('suppliers', doc.data(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      debugPrint('[SyncService] Pulled ${suppliersSnap.docs.length} suppliers');

      // Pull sales
      debugPrint('[SyncService] Pulling sales from cloud...');
      final salesSnap = await _firestore
          .collection('users')
          .doc(userId)
          .collection('sales')
          .get();
      for (final doc in salesSnap.docs) {
        await db.insert('daily_sales', doc.data(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      debugPrint('[SyncService] Pulled ${salesSnap.docs.length} sales');

      // Pull expenses
      debugPrint('[SyncService] Pulling expenses from cloud...');
      final expensesSnap = await _firestore
          .collection('users')
          .doc(userId)
          .collection('expenses')
          .get();
      for (final doc in expensesSnap.docs) {
        await db.insert('expenses', doc.data(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      debugPrint('[SyncService] Pulled ${expensesSnap.docs.length} expenses');

      debugPrint('[SyncService] ✓ All cloud data pulled and merged');
    } catch (e) {
      debugPrint('[SyncService] Cloud pull error: $e');
    } finally {
      _isSyncing = false;
    }
  }
}
