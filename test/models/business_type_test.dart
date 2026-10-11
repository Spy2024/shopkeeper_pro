import 'package:flutter_test/flutter_test.dart';
import 'package:shopkeeper_pro/models/business_type.dart';
import 'package:shopkeeper_pro/models/shop.dart';

void main() {
  group('BusinessTypes catalog', () {
    test('contains the agreed retail, transport, showroom and service types', () {
      final ids = BusinessTypes.all.map((type) => type.id).toSet();

      expect(ids.length, BusinessTypes.all.length);
      expect(ids, containsAll([
        'general_retail',
        'wholesale_distribution',
        'car_showroom',
        'motorcycle_showroom',
        'trucking_fleet',
        'passenger_transport',
        'goods_transport',
        'public_services',
        'private_services',
        'vehicle_workshop',
        'other',
      ]));
    });

    test('every business type has a label and at least one default module', () {
      for (final type in BusinessTypes.all) {
        expect(type.label.trim(), isNotEmpty, reason: type.id);
        expect(type.defaultModules, isNotEmpty, reason: type.id);
        expect(type.defaultModules.toSet().length, type.defaultModules.length,
            reason: 'Duplicate default module in ${type.id}');
      }
    });

    test('unknown business type falls back safely to general retail', () {
      expect(BusinessTypes.byId('not_a_real_type').id, 'general_retail');
      expect(BusinessTypes.byId(null).id, 'general_retail');
    });
  });

  test('shop business type survives map serialization and legacy maps default safely', () {
    final shop = Shop(
      id: 'shop-1',
      name: 'Demo',
      address: 'Karachi',
      phone: '03000000000',
      businessType: 'trucking_fleet',
    );

    final restored = Shop.fromMap(shop.toMap());
    expect(restored.businessType, 'trucking_fleet');

    final legacy = Shop.fromMap({
      'id': 'legacy-shop',
      'name': 'Legacy',
      'address': '',
      'phone': '',
    });
    expect(legacy.businessType, 'general_retail');
  });
}
