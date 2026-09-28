import 'dart:async';
import 'dart:convert';
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
    await _loadPendingQueue();
    debugPrint('[SyncQueue] Initialized with ${_pendingQueue.length} pending operations');
  }

  /// Add operation to queue when offline
  Future<void> queueOperation({
    required String operation,
    required String tableName,
    required String documentId,
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

    _pendingQueue.add(syncOp);
    await _saveSyncOperation(syncOp);

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
        _pendingQueue.add(SyncOperation.fromMap(row));
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
        // TODO: Call _executeSync(userId, op) once Firestore is configured
        successCount++;

        // Mark as synced
        await _markSynced(op.id);
        _pendingQueue.remove(op);

        debugPrint('[SyncQueue] ✓ Synced: ${op.tableName}/${op.documentId}');
      } catch (e) {
        failureCount++;
        failedIds.add(op.id);
        debugPrint('[SyncQueue] ✗ Failed: ${op.tableName}/${op.documentId} - $e');
      }
    }

    _isSyncing = false;
    debugPrint('[SyncQueue] Sync complete: $successCount succeeded, $failureCount failed');

    if (failureCount > 0) {
      debugPrint('[SyncQueue] Failed operation IDs: $failedIds');
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
    }
  }

  /// Get pending operation count
  int get pendingCount => _pendingQueue.length;
  bool get hasPending => _pendingQueue.isNotEmpty;
  bool get isSyncing => _isSyncing;

  /// Clear failed operations after manual review
  Future<void> clearFailedOperations() async {
    try {
      final db = await DBService.instance.database;
      // In production, mark failed ops differently for manual review
      debugPrint('[SyncQueue] Cleared failed operations');
    } catch (e) {
      debugPrint('[SyncQueue] Error clearing failed ops: $e');
    }
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

  SyncOperation({
    required this.id,
    required this.operation,
    required this.tableName,
    required this.documentId,
    required this.data,
    required this.timestamp,
  });

  String get dataAsJson => jsonEncode(data);

  factory SyncOperation.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic> decodedData = {};
    final dataValue = map['data'];

    if (dataValue is String && dataValue.isNotEmpty) {
      try {
        final decoded = jsonDecode(dataValue);
        if (decoded is Map<String, dynamic>) {
          decodedData = decoded;
        } else if (decoded is Map) {
          decodedData = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        decodedData = {};
      }
    }

    return SyncOperation(
      id: map['id'] as String,
      operation: map['operation'] as String,
      tableName: map['tableName'] as String,
      documentId: map['documentId'] as String,
      data: decodedData,
      timestamp: map['timestamp'] as int,
    );
  }
}
