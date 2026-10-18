import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'db_service.dart';

/// Manages offline changes queue and syncs to Firestore when online.
/// Implements local-first architecture with eventual consistency.
class SyncQueueService {
  SyncQueueService._internal();
  static final SyncQueueService instance = SyncQueueService._internal();

  final List<SyncOperation> _pendingQueue = [];
  bool _isSyncing = false;
  String? _activeUserId;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Queue operations table schema
  static const String queueTableName = 'sync_queue';
  static const String queueCreateSql = '''CREATE TABLE IF NOT EXISTS $queueTableName (
    id TEXT PRIMARY KEY,
    operation TEXT NOT NULL,
    tableName TEXT NOT NULL,
    documentId TEXT NOT NULL,
    data TEXT NOT NULL,
    timestamp INTEGER NOT NULL,
    synced INTEGER DEFAULT 0
  )''';

  /// Initialize queue from database
  Future<void> init(String userId) async {
    _activeUserId = userId;
    await _loadPendingQueue();
    debugPrint('[SyncQueue] Initialized with ${_pendingQueue.length} pending operations');
  }

  /// Add operation to queue when offline
  Future<void> queueOperation({
    required String operation, // 'create', 'update', 'delete'
    required String tableName, // 'products', 'bills', etc.
    required String documentId, // record ID
    required Map<String, dynamic> data,
  }) async {
    final syncOp = SyncOperation(
      id: '${tableName}_${documentId}_${DateTime.now().millisecondsSinceEpoch}',
      operation: operation,
      tableName: tableName,
      documentId: documentId,
      data: data,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    await _saveSyncOperation(syncOp);
    _pendingQueue.removeWhere((existing) => existing.id == syncOp.id);
    _pendingQueue.add(syncOp);

    debugPrint('[SyncQueue] Queued: $operation on $tableName/$documentId');
  }

  /// Save operation to local queue table
  Future<void> _saveSyncOperation(SyncOperation op) async {
    try {
      final db = await DBService.instance.database;
      await db.insert(
        queueTableName,
        {
          'id': op.id,
          'operation': op.operation,
          'tableName': op.tableName,
          'documentId': op.documentId,
          'data': op.dataAsJson,
          'timestamp': op.timestamp,
          'synced': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('[SyncQueue] Error saving operation: $e');
      rethrow;
    }
  }

  /// Load all pending operations from database
  Future<void> _loadPendingQueue() async {
    try {
      final db = await DBService.instance.database;
      final rows = await db.query(
        queueTableName,
        where: 'synced = ?',
        whereArgs: [0],
        orderBy: 'timestamp ASC',
      );

      _pendingQueue.clear();
      for (final row in rows) {
        _pendingQueue.add(SyncOperation.fromMap(row as Map<String, dynamic>));
      }

      debugPrint('[SyncQueue] Loaded ${_pendingQueue.length} pending operations');
    } catch (e) {
      debugPrint('[SyncQueue] Error loading queue: $e');
    }
  }

  /// Process queue and sync to Firestore
  Future<void> syncPendingOperations(String userId) async {
    if (_isSyncing || _pendingQueue.isEmpty) return;

    _isSyncing = true;
    debugPrint('[SyncQueue] Starting sync of ${_pendingQueue.length} operations');

    int successCount = 0;
    int failureCount = 0;
    final List<String> failedIds = [];

    for (final op in List<SyncOperation>.from(_pendingQueue)) {
      try {
        await _executeSync(userId, op);
        await _markSynced(op.id);
        _pendingQueue.removeWhere((queued) => queued.id == op.id);
        successCount++;
        debugPrint('[SyncQueue] ✓ Synced: ${op.tableName}/${op.documentId}');
      } catch (e) {
        failureCount++;
        failedIds.add(op.id);
        debugPrint('[SyncQueue] ✗ Failed: ${op.tableName}/${op.documentId} - $e');
      }
    }

    _isSyncing = false;
    debugPrint(
        '[SyncQueue] Sync complete: $successCount succeeded, $failureCount failed');

    if (failureCount > 0) {
      debugPrint('[SyncQueue] Failed operation IDs: $failedIds');
    }
  }

  Future<void> _executeSync(String userId, SyncOperation op) async {
    if (userId.trim().isEmpty) throw ArgumentError('A signed-in user ID is required for sync.');
    if (_activeUserId != null && _activeUserId != userId) {
      throw StateError('Sync queue user does not match the active account.');
    }
    const allowedTables = <String>{'shop', 'products', 'bills', 'bill_items', 'suppliers', 'supplier_orders', 'supplier_order_items', 'daily_sales', 'expenses', 'customers', 'customer_ledger', 'returns', 'return_items', 'payments', 'branches', 'branch_stock', 'branch_cash_entries', 'product_variants', 'mobile_devices', 'restaurant_tables', 'restaurant_orders', 'restaurant_menu_items', 'restaurant_order_items', 'restaurant_order_payments', 'vehicle_records', 'vehicle_transactions', 'transport_routes', 'transport_tickets', 'cargo_jobs', 'cargo_status_history', 'service_jobs', 'spare_part_compatibility', 'school_students', 'school_fees', 'clinic_patients', 'clinic_appointments', 'salon_services', 'salon_bookings', 'farm_plots', 'farm_activities', 'construction_projects', 'construction_tasks', 'public_service_cases'};
    if (!allowedTables.contains(op.tableName)) throw StateError('Unsupported sync table: ${op.tableName}');
    final ref = _firestore.collection('users').doc(userId).collection(op.tableName).doc(op.documentId);
    switch (op.operation) {
      case 'create':
      case 'update':
        await ref.set(op.data, SetOptions(merge: op.operation == 'update'));
        break;
      case 'delete':
        await ref.delete();
        break;
      default:
        throw StateError('Unsupported sync operation: ${op.operation}');
    }
  }

  /// Mark operation as synced
  Future<void> _markSynced(String opId) async {
    try {
      final db = await DBService.instance.database;
      await db.update(
        queueTableName,
        {'synced': 1},
        where: 'id = ?',
        whereArgs: [opId],
      );
    } catch (e) {
      debugPrint('[SyncQueue] Error marking as synced: $e');
      rethrow;
    }
  }

  Future<void> resetForLogout() async {
    _isSyncing = false;
    _pendingQueue.clear();
    _activeUserId = null;
  }

  /// Get pending operation count
  int get pendingCount => _pendingQueue.length;
  bool get hasPending => _pendingQueue.isNotEmpty;
  bool get isSyncing => _isSyncing;

  /// Clear failed operations after manual review
  Future<void> clearFailedOperations() async {
    // Failure details are not persisted in the current schema, so clearing
    // would risk deleting valid pending writes. Keep them until reviewed.
    debugPrint('[SyncQueue] Failed-operation deletion is disabled to protect pending writes.');
  }
}

/// Represents a single sync operation
class SyncOperation {
  final String id;
  final String operation;
  final String tableName;
  final String documentId;
  final Map<String, dynamic> data;
  final int timestamp;
  final int attempts;
  final int? nextRetryAt;
  final String? lastError;

  const SyncOperation({
    required this.id,
    required this.operation,
    required this.tableName,
    required this.documentId,
    required this.data,
    required this.timestamp,
    this.attempts = 0,
    this.nextRetryAt,
    this.lastError,
  });

  String get dataAsJson => jsonEncode(data);

  factory SyncOperation.fromMap(Map<String, dynamic> map) {
    final rawData = map['data'];
    final decodedData = rawData is String
        ? jsonDecode(rawData)
        : rawData;
    return SyncOperation(
      id: map['id'] as String,
      operation: map['operation'] as String,
      tableName: map['tableName'] as String,
      documentId: map['documentId'] as String,
      data: Map<String, dynamic>.from(decodedData as Map),
      timestamp: (map['timestamp'] as num).toInt(),
      attempts: (map['attempts'] as num?)?.toInt() ?? 0,
      nextRetryAt: (map['nextRetryAt'] as num?)?.toInt(),
      lastError: map['lastError'] as String?,
    );
  }
}
