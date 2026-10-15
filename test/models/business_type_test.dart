import 'package:flutter_test/flutter_test.dart';
import 'package:shopkeeper_pro/models/business_type.dart';
import 'package:shopkeeper_pro/models/business_branch.dart';
import 'package:shopkeeper_pro/models/shop.dart';

void main() {
  group('BusinessTypes catalog', () {
    test('contains the agreed retail, transport, showroom, service and spare-parts types', () {
      final ids = BusinessTypes.all.map((type) => type.id).toSet();

      expect(ids.length, BusinessTypes.all.length);
      expect(ids, containsAll([
        'general_retail',
        'wholesale_distribution',
        'mobile_electronics',
        'cosmetics',
        'car_showroom',
        'motorcycle_showroom',
        'trucking_fleet',
        'passenger_transport',
        'goods_transport',
        'public_services',
        'private_services',
        'vehicle_workshop',
        'spare_parts',
        'motorcycle_spare_parts',
        'car_spare_parts',
        'heavy_vehicle_spare_parts',
        'mobile_spare_parts',
        'computer_spare_parts',
        'home_appliance_spare_parts',
        'electrical_electronics_parts',
        'industrial_machinery_parts',
        'agricultural_machinery_parts',
        'generator_engine_parts',
        'plumbing_sanitary_parts',
        'other_spare_parts',
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

    test('mobile shop has the planned new/used/parts/repair module defaults', () {
      final mobile = BusinessTypes.byId('mobile_electronics');
      expect(mobile.label, contains('Mobile Shop'));
      expect(mobile.defaultModules, containsAll([
        'pos',
        'inventory',
        'purchases',
        'new_devices',
        'used_device_intake',
        'imei_tracking',
        'mobile_accessories',
        'mobile_parts',
        'repair_job_cards',
        'software_services',
        'device_condition_checklist',
        'warranty_tracking',
        'reports',
      ]));
    });

    test('cosmetics has inventory, expiry/batch and sales defaults', () {
      final cosmetics = BusinessTypes.byId('cosmetics');
      expect(cosmetics.label, contains('Cosmetics'));
      expect(cosmetics.defaultModules, containsAll([
        'pos',
        'inventory',
        'batch_expiry',
        'purchases',
        'customers',
        'reports',
      ]));
    });

    test('spare-parts types include part catalog and fitment-related modules', () {
      final types = BusinessTypes.all.where((type) => type.id.contains('spare_parts'));
      expect(types, isNotEmpty);
      for (final type in types) {
        expect(type.defaultModules, contains('part_catalog'), reason: type.id);
        expect(type.defaultModules, contains('inventory'), reason: type.id);
        expect(type.defaultModules, contains('purchases'), reason: type.id);
        expect(type.defaultModules, contains('stock_ledger'), reason: type.id);
      }
      expect(
        BusinessTypes.byId('mobile_spare_parts').defaultModules,
        contains('device_model_compatibility'),
      );
      expect(
        BusinessTypes.byId('car_spare_parts').defaultModules,
        contains('fitment_compatibility'),
      );
    });

    test('unknown business type falls back safely to general retail', () {
      expect(BusinessTypes.byId('not_a_real_type').id, 'general_retail');
      expect(BusinessTypes.byId(null).id, 'general_retail');
    });
  });

  group('Branch code validation', () {
    test('trims and uppercases valid codes', () {
      expect(normalizeBranchCode('  main_01 '), 'MAIN_01');
      expect(normalizeBranchCode('b-2'), 'B-2');
    });

    test('rejects blank, short, long and unsupported characters', () {
      for (final code in ['', 'A', 'BRANCH CODE', 'A/B', List.filled(21, 'X').join()]) {
        expect(() => normalizeBranchCode(code), throwsArgumentError, reason: code);
      }
    });
  });

  test('branch record preserves all profile fields and status flags', () {
    final branch = BusinessBranch(
      id: 'branch-1',
      name: 'Main Warehouse',
      code: 'MAIN_01',
      address: 'Karachi',
      phone: '03000000000',
      managerName: 'Manager',
      isMain: true,
      isActive: false,
      createdAt: DateTime.utc(2026, 1, 2),
    );

    final restored = BusinessBranch.fromMap(branch.toMap());
    expect(restored.id, 'branch-1');
    expect(restored.name, 'Main Warehouse');
    expect(restored.code, 'MAIN_01');
    expect(restored.address, 'Karachi');
    expect(restored.phone, '03000000000');
    expect(restored.managerName, 'Manager');
    expect(restored.isMain, isTrue);
    expect(restored.isActive, isFalse);
    expect(restored.createdAt, DateTime.utc(2026, 1, 2));
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
