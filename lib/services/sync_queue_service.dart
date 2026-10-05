import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'db_service.dart';

class SyncQueueService {
  SyncQueueService._internal();
  static final SyncQueueService instance = SyncQueueService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final List<SyncOperation> _pendingQueue = [];
  bool _isSyncing = false;
  Timer? _scheduledSync;
  static const queueTableName = 'sync_queue';

  Future<void> init(String userId) async => _loadPendingQueue();

  Future<void> queueOperation({
    required String operation,
    required String tableName,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    final now = DateTime.now().microsecondsSinceEpoch;
    final op = SyncOperation(
      id: '${tableName.replaceAll('/', '_')}_${documentId}_$now',
      operation: operation,
      tableName: tableName,
      documentId: documentId,
      data: data,
      timestamp: now,
    );
    final db = await DBService.instance.database;
    await db.insert(
      queueTableName,
      {
        'id': op.id,
        'operation': op.operation,
        'tableName': op.tableName,
        'documentId': op.documentId,
        'data': jsonEncode(op.data),
        'timestamp': op.timestamp,
        'synced': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _pendingQueue.add(op);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && uid.isNotEmpty) {
        _scheduledSync?.cancel();
        _scheduledSync = Timer(const Duration(milliseconds: 500), () {
          unawaited(syncPendingOperations(uid));
        });
      }
    } catch (e) {
      debugPrint('[SyncQueue] Firebase unavailable; operation remains offline: $e');
    }
  }

  Future<void> _loadPendingQueue() async {
    final db = await DBService.instance.database;
    final rows = await db.query(
      queueTableName,
      where: 'synced = ?',
      whereArgs: [0],
      orderBy: 'timestamp ASC',
    );
    _pendingQueue
      ..clear()
      ..addAll(rows.map(SyncOperation.fromMap));
  }

  DocumentReference<Map<String, dynamic>> _documentRef(
    String userId,
    String collectionPath,
    String documentId,
  ) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection(collectionPath)
        .doc(documentId);
  }

  Future<void> syncPendingOperations(String userId) async {
    if (_isSyncing) return;
    if (_pendingQueue.isEmpty) await _loadPendingQueue();
    if (_pendingQueue.isEmpty) return;

    _isSyncing = true;
    try {
      final db = await DBService.instance.database;
      for (final op in List<SyncOperation>.from(_pendingQueue)) {
        try {
          final ref = _documentRef(userId, op.tableName, op.documentId);
          if (op.operation == 'delete') {
            await ref.delete();
          } else {
            await ref.set(
              op.data,
              SetOptions(merge: op.operation == 'update'),
            );
          }
          await db.update(
            queueTableName,
            {'synced': 1},
            where: 'id = ?',
            whereArgs: [op.id],
          );
          _pendingQueue.remove(op);
        } catch (e) {
          debugPrint('[SyncQueue] failed ${op.id}: $e');
        }
      }
    } finally {
      _isSyncing = false;
    }
  }

  int get pendingCount => _pendingQueue.length;
  bool get hasPending => _pendingQueue.isNotEmpty;
  bool get isSyncing => _isSyncing;

  Future<void> dispose() async {
    _scheduledSync?.cancel();
    _scheduledSync = null;
  }

  Future<void> clearFailedOperations() async {
    final db = await DBService.instance.database;
    await db.delete(queueTableName, where: 'synced = 0');
    _pendingQueue.clear();
  }
}

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

  factory SyncOperation.fromMap(Map<String, dynamic> map) {
    final decoded = jsonDecode(map['data'] as String);
    return SyncOperation(
      id: map['id'] as String,
      operation: map['operation'] as String,
      tableName: map['tableName'] as String,
      documentId: map['documentId'] as String,
      data: decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{},
      timestamp: (map['timestamp'] as num).toInt(),
    );
  }
}