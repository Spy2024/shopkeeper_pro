import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'db_service.dart';

/// User-scoped local/cloud synchronization. Parent tables are processed before
/// their child tables so foreign-key relationships can be restored in order.
class SyncService {
  SyncService._internal();
  static final SyncService instance = SyncService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Connectivity _connectivity = Connectivity();
  bool _isOnline = true;
  bool _isSyncing = false;
  String? _activeUserId;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  bool get isOnline => _isOnline;
  bool get isSyncing => _isSyncing;

  // Local SQLite table -> Firestore collection.
  static const Map<String, String> _collections = {
    'shop': 'shop',
    'products': 'products',
    'customers': 'customers',
    'suppliers': 'suppliers',
    'supplier_orders': 'supplier_orders',
    'supplier_order_items': 'supplier_order_items',
    'bills': 'bills',
    'bill_items': 'bill_items',
    'payments': 'payments',
    'customer_ledger': 'customer_ledger',
    'daily_sales': 'sales', // retain the existing cloud collection name
    'expenses': 'expenses',
    'returns': 'returns',
    'return_items': 'return_items',
    'branches': 'branches',
    'branch_stock': 'branch_stock',
    'branch_cash_entries': 'branch_cash_entries',
    'product_variants': 'product_variants',
    'mobile_devices': 'mobile_devices',
    'restaurant_tables': 'restaurant_tables',
    'restaurant_orders': 'restaurant_orders',
    'vehicle_records': 'vehicle_records',
    'transport_routes': 'transport_routes',
    'transport_tickets': 'transport_tickets',
    'cargo_jobs': 'cargo_jobs',
    'service_jobs': 'service_jobs',
    'spare_part_compatibility': 'spare_part_compatibility',
    'school_students': 'school_students',
    'school_fees': 'school_fees',
    'clinic_patients': 'clinic_patients',
    'clinic_appointments': 'clinic_appointments',
    'salon_services': 'salon_services',
    'salon_bookings': 'salon_bookings',
    'farm_plots': 'farm_plots',
    'farm_activities': 'farm_activities',
    'construction_projects': 'construction_projects',
    'construction_tasks': 'construction_tasks',
    'public_service_cases': 'public_service_cases',
    'restaurant_menu_items': 'restaurant_menu_items',
    'restaurant_order_items': 'restaurant_order_items',
    'vehicle_transactions': 'vehicle_transactions',
    'cargo_status_history': 'cargo_status_history',
  };

  Future<void> init(String userId) async {
    _ensureActiveUser(userId);
    _activeUserId = userId;
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((result) {
      _isOnline = !result.contains(ConnectivityResult.none);
      if (_isOnline) {
        syncNow(userId);
      }
    });
    final current = await _connectivity.checkConnectivity();
    _isOnline = !current.contains(ConnectivityResult.none);
    if (_isOnline) await syncNow(userId);
  }

  Future<void> syncNow(String userId) async {
    _ensureActiveUser(userId);
    if (!_isOnline || _isSyncing) return;
    await syncFromCloud(userId);
    await _syncAll(userId);
  }

  void _ensureActiveUser(String userId) {
    if (userId.trim().isEmpty) throw ArgumentError('A signed-in UID is required.');
    if (DBService.instance.activeUserId != userId) {
      throw StateError('Refusing to sync: active SQLite account does not match Firebase UID.');
    }
    if (_activeUserId != null && _activeUserId != userId) {
      throw StateError('Refusing to sync: another user is active in SyncService.');
    }
  }

  CollectionReference<Map<String, dynamic>> _collection(String userId, String name) =>
      _firestore.collection('users').doc(userId).collection(name);

  String _documentId(String table, Map<String, Object?> row) {
    if (table == 'shop') return 'profile';
    final id = row['id'];
    if (id == null) throw StateError('Table $table has a row without an id.');
    return id.toString();
  }

  Future<void> _syncAll(String userId) async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      _ensureActiveUser(userId);
      final db = await DBService.instance.database;
      for (final entry in _collections.entries) {
        final rows = await db.query(entry.key);
        for (var offset = 0; offset < rows.length; offset += 400) {
          final batch = _firestore.batch();
          final end = (offset + 400 < rows.length) ? offset + 400 : rows.length;
          for (final row in rows.sublist(offset, end)) {
            final data = Map<String, dynamic>.from(row);
            final ref = _collection(userId, entry.value).doc(_documentId(entry.key, row));
            batch.set(ref, data, SetOptions(merge: true));
          }
          if (end > offset) await batch.commit();
        }
        debugPrint('[SyncService] Pushed ${rows.length} rows from ${entry.key}');
      }
    } catch (error, stackTrace) {
      debugPrint('[SyncService] Cloud push failed: $error\n$stackTrace');
    } finally {
      _isSyncing = false;
    }
  }

  /// Pulls each supported cloud collection into the active user's database.
  /// Existing rows are merged by primary key. Deletion tombstones/conflict
  /// resolution require an explicit change log and are not inferred from absence.
  Future<void> syncFromCloud(String userId) async {
    _ensureActiveUser(userId);
    if (_isSyncing || !_isOnline) return;
    _isSyncing = true;
    try {
      final db = await DBService.instance.database;
      for (final entry in _collections.entries) {
        final snapshot = await _collection(userId, entry.value).get();
        if (snapshot.docs.isEmpty) continue;
        await db.transaction((txn) async {
          for (final doc in snapshot.docs) {
            final data = Map<String, dynamic>.from(doc.data());
            data.putIfAbsent('id', () {
              if (entry.key == 'bill_items' || entry.key == 'supplier_order_items') {
                return int.tryParse(doc.id) ?? doc.id;
              }
              return doc.id;
            });
            await txn.insert(entry.key, data, conflictAlgorithm: ConflictAlgorithm.replace);
          }
        });
        debugPrint('[SyncService] Pulled ${snapshot.docs.length} rows into ${entry.key}');
      }
    } catch (error, stackTrace) {
      debugPrint('[SyncService] Cloud pull failed: $error\n$stackTrace');
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> dispose() async {
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _activeUserId = null;
  }
}
