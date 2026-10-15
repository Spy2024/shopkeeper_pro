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

  test('cloud child rows use stable cloud ID, not device-local SQLite ID', () {
    final cloud = prepareChildRowForCloud(
      {'id': 17, 'billId': 'bill-1', 'productName': 'Tea', 'quantity': 2},
      'item-cloud-1',
    );
    expect(cloud.containsKey('id'), isFalse);
    expect(cloud['cloudId'], 'item-cloud-1');
    expect(cloud['billId'], 'bill-1');
    expect(cloud['quantity'], 2);
  });

  test('downloaded child rows preserve cloud identity and strip server metadata', () {
    final local = prepareChildRowForLocal(
      {'id': 91, 'updatedAt': 'server-value', 'billId': 'bill-1', 'quantity': 2},
      'item-cloud-1',
    );
    expect(local.containsKey('id'), isFalse);
    expect(local.containsKey('updatedAt'), isFalse);
    expect(local['cloudId'], 'item-cloud-1');
    expect(local['billId'], 'bill-1');
  });
}
