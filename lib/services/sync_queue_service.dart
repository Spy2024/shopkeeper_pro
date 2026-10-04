import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'db_service.dart';

class SyncQueueService {
  SyncQueueService._internal();
  static final SyncQueueService instance = SyncQueueService._internal();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final List<SyncOperation> _pendingQueue = [];
  bool _isSyncing = false;
  static const queueTableName = 'sync_queue';

  Future<void> init(String userId) async { await _loadPendingQueue(); }

  Future<void> queueOperation({required String operation, required String tableName, required String documentId, required Map<String, dynamic> data}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final op = SyncOperation(id: '${tableName}_${documentId}_$now', operation: operation, tableName: tableName, documentId: documentId, data: data, timestamp: now);
    _pendingQueue.add(op);
    final db = await DBService.instance.database;
    await db.insert(queueTableName, {'id': op.id, 'operation': op.operation, 'tableName': op.tableName, 'documentId': op.documentId, 'data': jsonEncode(op.data), 'timestamp': op.timestamp, 'synced': 0}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _loadPendingQueue() async {
    final db = await DBService.instance.database;
    final rows = await db.query(queueTableName, where: 'synced = ?', whereArgs: [0], orderBy: 'timestamp ASC');
    _pendingQueue..clear()..addAll(rows.map((r) => SyncOperation.fromMap(r)));
  }

  Future<void> syncPendingOperations(String userId) async {
    if (_isSyncing || _pendingQueue.isEmpty) return;
    _isSyncing = true;
    try {
      final db = await DBService.instance.database;
      for (final op in List<SyncOperation>.from(_pendingQueue)) {
        try {
          final collection = _firestore.collection('users').doc(userId).collection(op.tableName);
          final ref = collection.doc(op.documentId);
          if (op.operation == 'delete') { await ref.delete(); } else { await ref.set(op.data, SetOptions(merge: op.operation == 'update')); }
          await db.update(queueTableName, {'synced': 1}, where: 'id = ?', whereArgs: [op.id]);
          _pendingQueue.remove(op);
        } catch (e) { debugPrint('[SyncQueue] failed ${op.id}: $e'); }
      }
    } finally { _isSyncing = false; }
  }

  int get pendingCount => _pendingQueue.length;
  bool get hasPending => _pendingQueue.isNotEmpty;
  bool get isSyncing => _isSyncing;
  Future<void> clearFailedOperations() async {}
}

class SyncOperation {
  final String id, operation, tableName, documentId;
  final Map<String, dynamic> data;
  final int timestamp;
  SyncOperation({required this.id, required this.operation, required this.tableName, required this.documentId, required this.data, required this.timestamp});
  factory SyncOperation.fromMap(Map<String, dynamic> map) => SyncOperation(id: map['id'] as String, operation: map['operation'] as String, tableName: map['tableName'] as String, documentId: map['documentId'] as String, data: jsonDecode(map['data'] as String) is Map ? Map<String, dynamic>.from(jsonDecode(map['data'] as String)) : {}, timestamp: map['timestamp'] as int);
}
