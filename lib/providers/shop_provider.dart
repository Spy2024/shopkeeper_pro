import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/shop.dart';
import '../services/db_service.dart';
import '../services/sync_queue_service.dart';

class ShopProvider extends ChangeNotifier {
  Shop? shop;
  final _uuid = const Uuid();

  Future<void> load() async {
    final db = await DBService.instance.database;
    final rows = await db.query('shop', limit: 1);
    if (rows.isNotEmpty) {
      shop = Shop.fromMap(Map<String, dynamic>.from(rows.first));
      notifyListeners();
    }
  }

  Future<void> save({
    required String name,
    required String address,
    required String phone,
    String? taxNumber,
    String? logoPath,
  }) async {
    if (name.trim().isEmpty || address.trim().isEmpty || phone.trim().isEmpty) {
      throw ArgumentError('Shop name, address and phone are required');
    }

    final db = await DBService.instance.database;
    final id = shop?.id ?? _uuid.v4();
    final newShop = Shop(
      id: id,
      name: name.trim(),
      address: address.trim(),
      phone: phone.trim(),
      taxNumber: taxNumber?.trim().isEmpty == true ? null : taxNumber?.trim(),
      logoPath: logoPath ?? shop?.logoPath,
    );

    await db.insert('shop', newShop.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    await db.delete('shop', where: 'id != ?', whereArgs: [id]);
    shop = newShop;

    try {
      await SyncQueueService.instance.queueOperation(
        operation: 'update',
        tableName: 'shop',
        documentId: 'profile',
        data: newShop.toMap(),
      );
    } catch (e) {
      debugPrint('[Shop] Queue deferred: $e');
    }

    notifyListeners();
  }
}
