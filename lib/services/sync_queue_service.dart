import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
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
    // Demo/local-only sessions have no Firebase app. When Firebase is
    // configured, however, an absent or different auth UID must fail closed.
    final firebaseConfigured = Firebase.apps.isNotEmpty;
    final authenticatedUid =
        firebaseConfigured ? FirebaseAuth.instance.currentUser?.uid : null;
    if ((firebaseConfigured && authenticatedUid != activeUserId) ||
        (authenticatedUid != null && authenticatedUid != activeUserId)) {
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
    final currentUid =
        firebaseConfigured ? FirebaseAuth.instance.currentUser?.uid : null;
    if (DBService.instance.activeUserId != activeUserId ||
        (firebaseConfigured && currentUid != activeUserId) ||
        (currentUid != null && currentUid != activeUserId)) {
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
    if (FirebaseAuth.instance.currentUser?.uid != userId ||
        DBService.instance.activeUserId != userId ||
        _pendingQueue.isEmpty ||
        _isSyncing) {
      return;
    }

    // Another caller may have finished loading the queue while this caller
    // was awaiting it; only one sync loop may acknowledge pending operations.
    _isSyncing = true;
    try {
      final db = await DBService.instance.database;
      if (FirebaseAuth.instance.currentUser?.uid != userId ||
          DBService.instance.activeUserId != userId) {
        return;
      }
      for (final op in List<SyncOperation>.from(_pendingQueue)) {
        try {
          // Account state can change while an earlier network write is in
          // flight. Stop before sending or acknowledging another account's work.
          if (FirebaseAuth.instance.currentUser?.uid != userId ||
              DBService.instance.activeUserId != userId) {
            return;
          }
          final ref = _documentRef(userId, op.tableName, op.documentId);
          if (op.operation == 'delete') {
            await ref.delete();
          } else {
            await ref.set(
              op.data,
              SetOptions(merge: op.operation == 'update'),
            );
          }
          if (FirebaseAuth.instance.currentUser?.uid != userId ||
              DBService.instance.activeUserId != userId) {
            // Leave the operation pending so the owning account can retry it.
            return;
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
    final activeUserId = DBService.instance.activeUserId;
    final authenticatedUid = FirebaseAuth.instance.currentUser?.uid;
    if (activeUserId == null ||
        activeUserId.isEmpty ||
        authenticatedUid != activeUserId) {
      throw StateError('Sign in with the account that owns this sync queue before clearing pending operations.');
    }

    final db = await DBService.instance.database;
    // Recheck ownership after awaiting database access to avoid clearing a
    // queue if the active account changed while the database was opening.
    if (DBService.instance.activeUserId != activeUserId ||
        FirebaseAuth.instance.currentUser?.uid != activeUserId) {
      throw StateError('The active account changed; pending operations were not cleared.');
    }
    await db.delete(queueTableName, where: 'synced = 0');
    if (_loadedQueueUserId == activeUserId) {
      _pendingQueue.clear();
    } else {
      await _loadPendingQueue(expectedUserId: activeUserId);
    }
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