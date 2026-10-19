import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/shop.dart';
import '../services/db_service.dart';
import 'package:sqflite/sqflite.dart';
import '../services/sync_queue_service.dart';

class ShopProvider extends ChangeNotifier {
  Shop? shop;
  final _uuid = const Uuid();

  Future<void> load() async {
    final db = await DBService.instance.database;
    final rows = await db.query('shop', limit: 1);
    shop = rows.isEmpty ? null : Shop.fromMap(rows.first);
    notifyListeners();
  }

  Future<void> save({
    required String name,
    required String address,
    required String phone,
    String? taxNumber,
    String? email,
    String? website,
    String? facebookUrl,
    String? instagramUrl,
    String? socialUrl,
    String? logoPath,
    String businessType = 'general_retail',
  }) async {
    final db = await DBService.instance.database;
    final id = shop?.id ?? _uuid.v4();
    final newShop = Shop(
      id: id,
      name: name,
      address: address,
      phone: phone,
      taxNumber: taxNumber,
      email: email?.trim().isEmpty == true ? null : email?.trim(),
      website: website?.trim().isEmpty == true ? null : website?.trim(),
      facebookUrl: facebookUrl?.trim().isEmpty == true ? null : facebookUrl?.trim(),
      instagramUrl: instagramUrl?.trim().isEmpty == true ? null : instagramUrl?.trim(),
      socialUrl: socialUrl?.trim().isEmpty == true ? null : socialUrl?.trim(),
      logoPath: logoPath ?? shop?.logoPath,
      businessType: businessType,
    );
    await db.insert('shop', newShop.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    await SyncQueueService.instance.queueOperation(operation: 'update', tableName: 'shop', documentId: 'profile', data: newShop.toMap());
    // single-row table: clear any stale duplicate from a previous insert
    await db.delete('shop', where: 'id != ?', whereArgs: [id]);
    shop = newShop;
    notifyListeners();
  }
}
