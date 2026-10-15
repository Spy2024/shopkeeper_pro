import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shopkeeper_pro/models/mobile_device.dart';
import 'package:shopkeeper_pro/services/db_service.dart';
import 'package:shopkeeper_pro/services/mobile_shop_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String userId;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    userId = 'mobile-${DateTime.now().microsecondsSinceEpoch}';
    await DBService.instance.clearActiveUser();
    await DBService.instance.configureForUser(userId);
  });

  tearDown(() async {
    if (DBService.instance.activeUserId == userId) {
      await DBService.instance.deleteActiveUserDatabase(userId);
    }
  });

  test('normalizes IMEI and rejects invalid or duplicate pair', () {
    expect(normalizeImei('35-123456-789012-3'), '351234567890123');
    expect(() => validateImeiPair('123', null), throwsArgumentError);
    expect(
      () => validateImeiPair('351234567890123', '351234567890123'),
      throwsArgumentError,
    );
  });

  test('used mobile intake starts in inspection and tracks full known cost', () async {
    final device = await MobileShopService.instance.createDevice(
      deviceType: 'used',
      brand: 'Samsung',
      model: 'Galaxy S22',
      imei1: '351234567890123',
      purchasePrice: 42000,
      repairCost: 2500,
      sellingPrice: 49000,
      conditionGrade: 'B',
      inspection: const {'screen': 'pass', 'charging': 'needs_repair'},
    );

    expect(device.status, 'inspection_pending');
    expect(device.totalKnownCost, 44500);
    expect(device.expectedMargin, 4500);

    final rows = await MobileShopService.instance.listDevices(
      deviceType: 'used',
      status: 'inspection_pending',
      search: '351234567890123',
    );
    expect(rows.map((item) => item.id), contains(device.id));
    expect(rows.single.inspection['screen'], 'pass');
  });

  test('duplicate IMEI cannot be registered across IMEI fields', () async {
    await MobileShopService.instance.createDevice(
      deviceType: 'new',
      brand: 'Apple',
      model: 'iPhone',
      imei1: '351234567890123',
    );

    await expectLater(
      MobileShopService.instance.createDevice(
        deviceType: 'used',
        brand: 'Apple',
        model: 'iPhone',
        imei2: '351234567890123',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('device status update cannot silently put a sold phone back in stock', () async {
    final device = await MobileShopService.instance.createDevice(
      deviceType: 'new',
      brand: 'Xiaomi',
      model: 'Redmi Note',
      imei1: '351234567890124',
    );
    await MobileShopService.instance.updateDeviceStatus(device.id, 'sold');

    await expectLater(
      MobileShopService.instance.updateDeviceStatus(device.id, 'in_stock'),
      throwsA(isA<StateError>()),
    );
  });

  test('repair jobs require customer consent before work starts', () async {
    final device = await MobileShopService.instance.createDevice(
      deviceType: 'used',
      brand: 'Samsung',
      model: 'A54',
      imei1: '351234567890125',
    );
    final job = await MobileShopService.instance.createRepairJob(
      jobNumber: 'JOB-001',
      customerName: 'Test Customer',
      customerPhone: '03001234567',
      deviceId: device.id,
      brand: 'Samsung',
      model: 'A54',
      reportedIssue: 'Charging not working',
      estimateAmount: 3000,
      approvedAmount: 2500,
      advancePaid: 500,
      customerConsent: false,
    );
    expect(job.balanceDue, 2000);

    await expectLater(
      MobileShopService.instance.updateRepairJobStatus(job.id, 'in_progress'),
      throwsA(isA<StateError>()),
    );

    final jobs = await MobileShopService.instance.listRepairJobs(
      status: 'received',
      search: 'JOB-001',
    );
    expect(jobs.single.id, job.id);
  });

  test('repair job number is unique', () async {
    await MobileShopService.instance.createRepairJob(
      jobNumber: 'JOB-DUP',
      customerName: 'Test Customer',
      reportedIssue: 'Broken screen',
    );
    await expectLater(
      MobileShopService.instance.createRepairJob(
        jobNumber: 'JOB-DUP',
        customerName: 'Test Customer',
        reportedIssue: 'Broken screen',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('negative and non-finite prices are rejected', () async {
    await expectLater(
      MobileShopService.instance.createDevice(
        deviceType: 'new',
        brand: 'Apple',
        model: 'iPhone',
        purchasePrice: double.nan,
      ),
      throwsArgumentError,
    );
  });
}
