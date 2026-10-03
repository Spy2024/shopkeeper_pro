import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/shop.dart';
import '../services/db_service.dart';

class ShopProvider extends ChangeNotifier {
  Shop? shop;
  final _uuid = const Uuid();

  Future<void> load() async {
    final db = await DBService.instance.database;
    final rows = await db.query('shop', limit: 1);
    if (rows.isNotEmpty) {
      shop = Shop.fromMap(rows.first);
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
    await db.insert('shop', newShop.toMap());
    // single-row table: clear any stale duplicate from a previous insert
    await db.delete('shop', where: 'id != ?', whereArgs: [id]);
    shop = newShop;
    notifyListeners();
  }
}
