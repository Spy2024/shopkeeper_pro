import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/shop.dart';
import '../services/db_service.dart';

class ShopProvider extends ChangeNotifier {
  Shop? shop;
  final _uuid = const Uuid();

  Future<void> load() async {
    try {
      final db = await DBService.instance.database;
      final rows = await db.query('shop', limit: 1);
      if (rows.isNotEmpty) {
        shop = Shop.fromMap(rows.first);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[ShopProvider] Error loading shop: $e');
    }
  }

  Future<void> save({
    required String name,
    required String address,
    required String phone,
    String? taxNumber,
    String? logoPath,
  }) async {
    try {
      final db = await DBService.instance.database;
      final id = shop?.id ?? _uuid.v4();
      final newShop = Shop(
        id: id,
        name: name,
        address: address,
        phone: phone,
        taxNumber: taxNumber,
        logoPath: logoPath ?? shop?.logoPath,
      );

      final existing = await db.query('shop', limit: 1);
      if (existing.isEmpty) {
        await db.insert('shop', newShop.toMap());
      } else {
        await db.update(
          'shop',
          newShop.toMap(),
          where: 'id = ?',
          whereArgs: [id],
        );
      }

      await db.delete('shop', where: 'id != ?', whereArgs: [id]);
      shop = newShop;
      notifyListeners();
    } catch (e) {
      debugPrint('[ShopProvider] Error saving shop: $e');
      rethrow;
    }
  }
}
