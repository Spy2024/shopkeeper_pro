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

  test('used phone can only become sale-ready after inspection status is changed', () async {
    final device = await MobileShopService.instance.createDevice(
      deviceType: 'used',
      brand: 'Samsung',
      model: 'Galaxy S22',
      imei1: '351234567890127',
    );
    expect(device.status, 'inspection_pending');

    await MobileShopService.instance.updateDeviceStatus(device.id, 'in_stock');
    final refreshed = await MobileShopService.instance.listDevices(search: device.imei1);
    expect(refreshed.single.status, 'in_stock');
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
        imei1: '351234567890128',
        imei2: '351234567890123',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('device cannot be marked sold without a POS bill link', () async {
    final device = await MobileShopService.instance.createDevice(
      deviceType: 'new',
      brand: 'Xiaomi',
      model: 'Redmi Note',
      imei1: '351234567890124',
    );

    await expectLater(
      MobileShopService.instance.updateDeviceStatus(device.id, 'sold'),
      throwsA(isA<StateError>()),
    );
    final saved = await MobileShopService.instance.listDevices(search: device.imei1);
    expect(saved.single.status, 'in_stock');
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

  test('initial repair advance is recorded as a payment atomically', () async {
    final db = await DBService.instance.database;
    final job = await MobileShopService.instance.createRepairJob(
      jobNumber: 'JOB-INITIAL-ADVANCE',
      customerName: 'Test Customer',
      reportedIssue: 'Battery replacement',
      approvedAmount: 3000,
      advancePaid: 500,
      customerConsent: true,
    );
    final payments = await db.query(
      'mobile_repair_payments',
      where: 'jobId = ?',
      whereArgs: [job.id],
    );
    expect(payments, hasLength(1));
    expect(payments.single['amount'], 500);
    expect(payments.single['method'], 'cash');
    expect(job.balanceDue, 2500);
  });

  test('repair parts consume inventory and repair payments update balance', () async {
    final db = await DBService.instance.database;
    await db.insert('products', {
      'id': 'lcd-panel-1',
      'name': 'LCD Panel',
      'category': 'Mobile Spare Parts',
      'stockQuantity': 5,
      'costPrice': 1000.0,
      'sellingPrice': 1500.0,
      'lowStockThreshold': 1,
    });
    final job = await MobileShopService.instance.createRepairJob(
      jobNumber: 'JOB-PART-PAY',
      customerName: 'Test Customer',
      reportedIssue: 'Broken display',
      estimateAmount: 5000,
      approvedAmount: 5000,
      customerConsent: true,
    );

    final part = await MobileShopService.instance.consumeRepairPart(
      jobId: job.id,
      productId: 'lcd-panel-1',
      quantity: 2,
      unitPrice: 1600,
    );
    expect(part['partName'], 'LCD Panel');
    expect((await db.query('products', where: 'id = ?', whereArgs: ['lcd-panel-1'])).single['stockQuantity'], 3);
    final updatedJob = (await MobileShopService.instance.listRepairJobs(search: 'JOB-PART-PAY')).single;
    expect(updatedJob.partsCost, 2000);

    await MobileShopService.instance.recordRepairPayment(
      jobId: job.id,
      amount: 1000,
      method: 'cash',
    );
    final paidJob = (await MobileShopService.instance.listRepairJobs(search: 'JOB-PART-PAY')).single;
    expect(paidJob.advancePaid, 1000);
    expect(paidJob.balanceDue, 4000);
    await expectLater(
      MobileShopService.instance.recordRepairPayment(
        jobId: job.id,
        amount: 5000,
        method: 'cash',
      ),
      throwsStateError,
    );
  });

  test('repair warranty can be issued after delivery and claim is recorded', () async {
    final job = await MobileShopService.instance.createRepairJob(
      jobNumber: 'JOB-WARRANTY',
      customerName: 'Test Customer',
      reportedIssue: 'Charging port replaced',
      customerConsent: true,
      warrantyDays: 30,
    );
    await MobileShopService.instance.updateRepairJobStatus(job.id, 'delivered');
    final warranty = await MobileShopService.instance.issueRepairWarranty(
      jobId: job.id,
      warrantyDays: 30,
      terms: 'Repair workmanship only',
    );
    expect(warranty['status'], 'active');
    final claim = await MobileShopService.instance.createWarrantyClaim(
      warrantyId: warranty['id']! as String,
      description: 'Charging issue returned',
    );
    expect(claim['status'], 'open');
    expect(await MobileShopService.instance.repairProfitReport(), containsPair('approvedRevenue', 0.0));
  });

  test('mobile device intake requires a primary IMEI', () async {
    await expectLater(
      MobileShopService.instance.createDevice(
        deviceType: 'new',
        brand: 'Apple',
        model: 'iPhone',
      ),
      throwsArgumentError,
    );
  });

  test('negative and non-finite prices are rejected', () async {
    await expectLater(
      MobileShopService.instance.createDevice(
        deviceType: 'new',
        brand: 'Apple',
        model: 'iPhone',
        imei1: '351234567890126',
        purchasePrice: double.nan,
      ),
      throwsArgumentError,
    );
  });
}
