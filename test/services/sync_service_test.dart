import 'package:flutter_test/flutter_test.dart';
import 'package:shopkeeper_pro/models/product.dart';
import 'package:shopkeeper_pro/services/sync_service.dart';

void main() {
  test('sync service starts in a defined non-syncing state', () {
    expect(SyncService.instance.isSyncing, isFalse);
    final product = Product(id: 'p1', name: 'Tea', category: 'Grocery',
      stockQuantity: 10, costPrice: 80, sellingPrice: 100);
    expect(product.toMap()['id'], 'p1');
  });
}
