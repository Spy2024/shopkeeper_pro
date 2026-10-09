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

  FirebaseFirestore? _firestore;
  FirebaseFirestore get _dbFirestore => _firestore ??= FirebaseFirestore.instance;
  final List<SyncOperation> _pendingQueue = [];
  bool _isSyncing = false;
  String? _loadedQueueUserId;
  Timer? _scheduledSync;
  static const queueTableName = 'sync_queue';

  Future<void> init(String userId) async {
    if (userId.trim().isEmpty || DBService.instance.activeUserId != userId) {
      _pendingQueue.clear();
      _loadedQueueUserId = null;
      return;
    }
    await _loadPendingQueue(expectedUserId: userId);
  }

  Future<void> queueOperation({
    required String operation,
    required String tableName,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    final activeUserId = DBService.instance.activeUserId;
    if (activeUserId == null || activeUserId.trim().isEmpty) {
      throw StateError('Sign in before adding operations to the sync queue.');
    }
    final authenticatedUid = FirebaseAuth.instance.currentUser?.uid;
    if (authenticatedUid != null && authenticatedUid != activeUserId) {
      throw StateError('The active database does not belong to the authenticated account.');
    }
    if (_loadedQueueUserId != activeUserId) {
      await _loadPendingQueue(expectedUserId: activeUserId);
    }
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
    if (DBService.instance.activeUserId != activeUserId ||
        (FirebaseAuth.instance.currentUser?.uid != null &&
            FirebaseAuth.instance.currentUser?.uid != activeUserId)) {
      throw StateError('The active account changed before the sync operation was saved.');
    }
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

  Future<void> reloadPendingQueue() => _loadPendingQueue();

  Future<void> _loadPendingQueue({String? expectedUserId}) async {
    final activeUserId = DBService.instance.activeUserId;
    if (activeUserId == null ||
        (expectedUserId != null && activeUserId != expectedUserId)) {
      _pendingQueue.clear();
      _loadedQueueUserId = null;
      return;
    }
    final db = await DBService.instance.database;
    if (DBService.instance.activeUserId != activeUserId) {
      _pendingQueue.clear();
      _loadedQueueUserId = null;
      return;
    }
    final rows = await db.query(
      queueTableName,
      where: 'synced = ?',
      whereArgs: [0],
      orderBy: 'timestamp ASC',
    );
    if (DBService.instance.activeUserId != activeUserId) {
      _pendingQueue.clear();
      _loadedQueueUserId = null;
      return;
    }
    _pendingQueue
      ..clear()
      ..addAll(rows.map(SyncOperation.fromMap));
    _loadedQueueUserId = activeUserId;
  }

  DocumentReference<Map<String, dynamic>> _documentRef(
    String userId,
    String collectionPath,
    String documentId,
  ) {
    return _dbFirestore
        .collection('users')
        .doc(userId)
        .collection(collectionPath)
        .doc(documentId);
  }

  Future<void> syncPendingOperations(String userId) async {
    // Never write local queued data to a different or unauthenticated account.
    if (userId.trim().isEmpty ||
        FirebaseAuth.instance.currentUser?.uid != userId ||
        DBService.instance.activeUserId != userId) {
      return;
    }
    if (_isSyncing) return;
    if (_loadedQueueUserId != userId) {
      await _loadPendingQueue(expectedUserId: userId);
    } else if (_pendingQueue.isEmpty) {
      await _loadPendingQueue(expectedUserId: userId);
    }
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