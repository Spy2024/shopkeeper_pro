import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sqflite/sqflite.dart';
import 'db_service.dart';

class SyncQueueService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> enqueue({
    required String entityType,
    required String entityId,
    required String action,
    required Map<String, dynamic> payload,
  }) async {
    final db = await DBService.instance.database;

    await db.insert('sync_queue', {
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'entityType': entityType,
      'entityId': entityId,
      'action': action,
      'payload': jsonEncode(payload),
      'createdAt': DateTime.now().toIso8601String(),
      'syncedAt': null,
    });
  }

  Future<void> processPendingSyncs() async {
    final db = await DBService.instance.database;
    final pending = await db.query(
      'sync_queue',
      where: 'syncedAt IS NULL',
      orderBy: 'createdAt ASC',
    );

    for (final row in pending) {
      final entityType = row['entityType'] as String;
      final entityId = row['entityId'] as String;
      final action = row['action'] as String;
      final payload = jsonDecode(row['payload'] as String) as Map<String, dynamic>;

      try {
        await _syncOne(entityType: entityType, entityId: entityId, action: action, payload: payload);
        await db.update(
          'sync_queue',
          {'syncedAt': DateTime.now().toIso8601String()},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      } catch (_) {
        break;
      }
    }
  }

  Future<void> _syncOne({
    required String entityType,
    required String entityId,
    required String action,
    required Map<String, dynamic> payload,
  }) async {
    final collection = _firestore.collection(entityType);

    switch (action) {
      case 'create':
      case 'update':
        await collection.doc(entityId).set(payload, SetOptions(merge: true));
        break;
      case 'delete':
        await collection.doc(entityId).delete();
        break;
      default:
        throw ArgumentError('Unsupported sync action: $action');
    }
  }
}
