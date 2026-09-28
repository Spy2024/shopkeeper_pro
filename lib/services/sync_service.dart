import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../models/bill.dart';
import '../models/product.dart';
import '../models/supplier.dart';
import '../models/shop.dart';
import '../models/daily_sale.dart';
import 'db_service.dart';

/// Multi-device sync service using Firebase Firestore.
/// Syncs local SQLite changes to cloud and vice versa.
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
      _isOnline = result != ConnectivityResult.none;
      if (_isOnline) _syncAll(userId);
    });
  }

  /// Sync all local data to Firebase
  Future<void> _syncAll(String userId) async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final db = await DBService.instance.database;

      // Sync shop profile
      final shopRows = await db.query('shop', limit: 1);
      if (shopRows.isNotEmpty) {
        await _firestore.collection('users').doc(userId).collection('shop').doc('profile').set(
          shopRows.first,
          SetOptions(merge: true),
        );
      }

      // Sync products
      final products = await db.query('products');
      final batch = _firestore.batch();
      for (final product in products) {
        final ref = _firestore
            .collection('users')
            .doc(userId)
            .collection('products')
            .doc(product['id'] as String);
        batch.set(ref, product, SetOptions(merge: true));
      }
      await batch.commit();

      // Sync bills
      final bills = await db.query('bills');
      final billBatch = _firestore.batch();
      for (final bill in bills) {
        final ref = _firestore
            .collection('users')
            .doc(userId)
            .collection('bills')
            .doc(bill['id'] as String);
        billBatch.set(ref, bill, SetOptions(merge: true));
      }
      await billBatch.commit();

      // Sync suppliers
      final suppliers = await db.query('suppliers');
      final supplierBatch = _firestore.batch();
      for (final supplier in suppliers) {
        final ref = _firestore
            .collection('users')
            .doc(userId)
            .collection('suppliers')
            .doc(supplier['id'] as String);
        supplierBatch.set(ref, supplier, SetOptions(merge: true));
      }
      await supplierBatch.commit();

      // Sync sales
      final sales = await db.query('daily_sales');
      final salesBatch = _firestore.batch();
      for (final sale in sales) {
        final ref = _firestore
            .collection('users')
            .doc(userId)
            .collection('sales')
            .doc(sale['id'] as String);
        salesBatch.set(ref, sale, SetOptions(merge: true));
      }
      await salesBatch.commit();

      // Sync expenses
      final expenses = await db.query('expenses');
      final expenseBatch = _firestore.batch();
      for (final expense in expenses) {
        final ref = _firestore
            .collection('users')
            .doc(userId)
            .collection('expenses')
            .doc(expense['id'] as String);
        expenseBatch.set(ref, expense, SetOptions(merge: true));
      }
      await expenseBatch.commit();
    } catch (e) {
      debugPrint('Sync error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Download cloud data and merge with local SQLite
  Future<void> syncFromCloud(String userId) async {
    if (_isSyncing || !_isOnline) return;
    _isSyncing = true;

    try {
      final db = await DBService.instance.database;

      // Sync shop
      final shopSnap =
          await _firestore.collection('users').doc(userId).collection('shop').doc('profile').get();
      if (shopSnap.exists) {
        await db.update('shop', shopSnap.data()!, where: '1=1');
      }

      // Sync products
      final productsSnap =
          await _firestore.collection('users').doc(userId).collection('products').get();
      for (final doc in productsSnap.docs) {
        await db.insert('products', doc.data(), conflictAlgorithm: ConflictAlgorithm.replace);
      }

      // Sync bills, suppliers, sales, expenses similarly...
    } catch (e) {
      debugPrint('Cloud sync error: $e');
    } finally {
      _isSyncing = false;
    }
  }
}
