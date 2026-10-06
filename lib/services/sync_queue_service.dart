import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'db_service.dart';

class SyncQueueService {
  SyncQueueService._internal();
  static final SyncQueueService instance = SyncQueueService._internal();

  static const String queueTableName = 'sync_queue';
  static const int _maxAttempts = 6;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final List<SyncOperation> _pendingQueue = <SyncOperation>[];
  bool _isSyncing = false;

  static const Map<String, String> _collectionByTable = {
    'products': 'products',
    'bills': 'bills',
    'bill_items': 'bill_items',
    'suppliers': 'suppliers',
    'supplier_orders': 'supplier_orders',
    'supplier_order_items': 'supplier_order_items',
    'daily_sales': 'sales',
    'expenses': 'expenses',
  };

  Future<void> init(String userId) async {
    await _loadPendingQueue();
    debugPrint('[SyncQueue] Initialized with ${_pendingQueue.length} pending operations');
  }

  Future<void> queueOperation({
    required String operation,
    required String tableName,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    final normalizedOperation = operation.toLowerCase();
    if (!{'create', 'update', 'delete'}.contains(normalizedOperation)) {
      throw ArgumentError.value(operation, 'operation', 'Expected create, update or delete');
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final syncOp = SyncOperation(
      id: '${tableName}_${documentId}_§timestamp',
      operation: normalizedOperation,
      tableName: tableName,
      documentId: documentId,
      data: Map<String, dynamic>.from(data),
      timestamp: timestamp,
    );

    final db = await DBService.instance.database;
    await db.transaction((txn) async {
      await txn.insert(queueTableName, {
        'id': syncOp.id,
        'operation': syncOp.operation,
        'tableName': syncOp.tableName,
        'documentId': syncOp.documentId,
        'data': syncOp.dataAsJson,
        'timestamp': syncOp.timestamp,
        'synced': 0,
        'attempts': 0,
        'nextRetryAt': null,
        'lastError': null,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('sync_metadata', {
        'tableName': syncOp.tableName,
        'documentId': syncOp.documentId,
        'updatedAt': syncOp.timestamp,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });

    _pendingQueue.add(syncOp);
    _pendingQueue.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  Future<void> _loadPendingQueue() async {
    final db = await DBService.instance.database;
    final rows = await db.query(queueTableName,
        where: 'synced = ?', whereArgs: [0], orderBy: 'timestamp ASC');
    _pendingQueue
      ..clear()
      ..addAll(rows.map((row) => SyncOperation.fromMap(Map<String, dynamic>.from(row))));
  }

  Future<void> syncPendingOperations(String userId) async {
    if (_isSyncing) return;
    await _loadPendingQueue();
    if (_pendingQueue.isEmpty) return;

    _isSyncing = true;
    var successCount = 0;
    var failureCount = 0;
    try {
      for (final op in List<SyncOperation>.from(_pendingQueue)) {
        if (op.nextRetryAt != null &&
            op.nextRetryAt! > DateTime.now().millisecondsSinceEpoch) {
          continue;
        }
        try {
          await _executeWithRetry(userId, op);
          await _markSynced(op.id);
          _pendingQueue.removeWhere((item) => item.id == op.id);
          successCount++;
        } catch (e) {
          await _recordFailure(op, e);
          failureCount++;
        }
      }
    } finally {
      _isSyncing = false;
    }
    debugPrint('[SyncQueue] Sync complete: ${successCount} succeeded, ${failureCount} failed');
  }

  Future<void> _executeWithRetry(String userId, SyncOperation op) async {
    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        await _executeSync(userId, op);
        return;
      } catch (e) {
        lastError = e;
        if (attempt < 3) {
          await Future<void>.delayed(
            Duration(milliseconds: 250 * (1 << (attempt - 1))),
          );
        }
      }
    }
    throw lastError ?? StateError('Sync operation failed');
  }

  Future<void> _executeSync(String userId, SyncOperation op) async {
    final collection = _collectionByTable[op.tableName];
    final isShop = op.tableName == 'shop';
    if (collection == null && !isShop) {
      throw StateError('Unsupported sync table: ${op.tableName}');
    }

    final ref = isShop
        ? _firestore.collection('users').doc(userId).collection('shop').doc('profile')
        : _firestore.collection('users').doc(userId).collection(collection!).doc(op.documentId);

    await _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(ref);
      final cloudData = existing.data();
      final cloudTimestamp = (cloudData?['_syncUpdatedAt'] as num?)?.toInt() ?? -1;
      if (cloudTimestamp > op.timestamp) return;

      if (op.operation == 'delete') {
        transaction.set(ref, {
          '_deleted': true,
          '_syncUpdatedAt': op.timestamp,
          'id': op.documentId,
        }, SetOptions(merge: false));
        return;
      }

      transaction.set(ref, {
        ...op.data,
        '_deleted': false,
        '_syncUpdatedAt': op.timestamp,
      }, SetOptions(merge: true));
    });
  }

  Future<void> _markSynced(String opId) async {
    final db = await DBService.instance.database;
    await db.update(queueTableName, {'synced': 1, 'lastError': null},
        where: 'id = ?', whereArgs: [opId]);
  }

  Future<void> _recordFailure(SyncOperation op, Object error) async {
    final db = await DBService.instance.database;
    final attempts = op.attempts + 1;
    final delaySeconds = 1 << attempts.clamp(0, 5);
    final nextRetryAt = DateTime.now().add(Duration(seconds: delaySeconds)).millisecondsSinceEpoch;
    await db.update(queueTableName, {
      'attempts': attempts,
      'nextRetryAt': nextRetryAt,
      'lastError': error.toString(),
    }, where: 'id = ?', whereArgs: [op.id]);
    final index = _pendingQueue.indexWhere((item) => item.id == op.id);
    if (index != -1) {
      _pendingQueue[index] = op.copyWith(
        attempts: attempts, nextRetryAt: nextRetryAt, lastError: error.toString());
    }
  }

  int get pendingCount => _pendingQueue.length;
  bool get hasPending => _pendingQueue.isNotEmpty;
  bool get isSyncing => _isSyncing;

  Future<void> clearFailedOperations() async {
    final db = await DBService.instance.database;
    await db.delete(queueTableName,
        where: 'synced = ? AND attempts >= ?', whereArgs: [0, _maxAttempts]);
    _pendingQueue.removeWhere((op) => op.attempts >= _maxAttempts);
  }
}

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
    var decoded = <String, dynamic>{};
    final rawData = map['data'];
    if (rawData is String && rawData.isNotEmpty) {
      try {
        final value = jsonDecode(rawData);
        if (value is Map) decoded = Map<String, dynamic>.from(value);
      } catch (_) {}
    }
    return SyncOperation(
      id: map['id'] as String,
      operation: map['operation'] as String,
      tableName: map['tableName'] as String,
      documentId: map['documentId'] as String,
      data: decoded,
      timestamp: (map['timestamp'] as num).toInt(),
      attempts: (map['attempts'] as num?)?.toInt() ?? 0,
      nextRetryAt: (map['nextRetryAt'] as num?)?.toInt(),
      lastError: map['lastError'] as String?,
    );
  }

  SyncOperation copyWith({int? attempts, int? nextRetryAt, String? lastError}) {
    return SyncOperation(
      id: id,
      operation: operation,
      tableName: tableName,
      documentId: documentId,
      data: data,
      timestamp: timestamp,
      attempts: attempts ?? this.attempts,
      nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      lastError: lastError ?? this.lastError,
    );
  }
}
