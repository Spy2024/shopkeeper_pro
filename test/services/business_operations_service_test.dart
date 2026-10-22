import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shopkeeper_pro/services/business_operations_service.dart';
import 'package:shopkeeper_pro/services/db_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final ops = BusinessOperationsService.instance;
  late String userId;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    userId = 'business-vertical-${DateTime.now().microsecondsSinceEpoch}';
    await DBService.instance.clearActiveUser();
    await DBService.instance.configureForUser(userId);
  });

  tearDown(() async {
    if (DBService.instance.activeUserId == userId) {
      await DBService.instance.deleteActiveUserDatabase(userId);
    }
  });

  test('restaurant split payment must match total and order cannot close unpaid', () async {
    final tableId = await ops.createRestaurantTable(name: 'T-1', capacity: 4);
    final orderId = await ops.createRestaurantOrder(tableId: tableId);
    final menuId = await ops.addRestaurantMenuItem(name: 'Biryani', category: 'Main', price: 450);
    final itemId = await ops.addRestaurantOrderItem(orderId: orderId, menuItemId: menuId, quantity: 2);
    final db = await DBService.instance.database;

    expect((await db.query('restaurant_orders', where: 'id = ?', whereArgs: [orderId])).single['total'], 900);
    await expectLater(ops.completeRestaurantOrder(orderId), throwsStateError);
    await expectLater(
      ops.recordRestaurantPayment(orderId: orderId, payments: const [PaymentLine(method: 'cash', amount: 800)]),
      throwsStateError,
    );

    await ops.recordRestaurantPayment(orderId: orderId, payments: const [
      PaymentLine(method: 'cash', amount: 400),
      PaymentLine(method: 'card', amount: 500, reference: 'txn-1'),
    ]);
    await expectLater(
      ops.recordRestaurantPayment(orderId: orderId, payments: const [PaymentLine(method: 'cash', amount: 900)]),
      throwsStateError,
    );
    await ops.updateKitchenStatus(orderItemId: itemId, status: 'preparing');
    await expectLater(ops.completeRestaurantOrder(orderId), throwsStateError);
    await ops.updateKitchenStatus(orderItemId: itemId, status: 'served');
    await ops.completeRestaurantOrder(orderId);

    expect((await db.query('restaurant_orders', where: 'id = ?', whereArgs: [orderId])).single['status'], 'completed');
    expect((await db.query('restaurant_tables', where: 'id = ?', whereArgs: [tableId])).single['status'], 'available');
    expect(await db.query('restaurant_order_payments', where: 'orderId = ?', whereArgs: [orderId]), hasLength(2));
  });

  test('school fee payments update balance and reject overpayment', () async {
    final studentId = await ops.addSchoolStudent(name: 'Student A', guardianName: 'Guardian');
    final feeId = await ops.addSchoolFee(studentId: studentId, amount: 1000, paidAmount: 200);
    final db = await DBService.instance.database;

    await ops.recordSchoolFeePayment(feeId: feeId, amount: 300);
    var fee = (await db.query('school_fees', where: 'id = ?', whereArgs: [feeId])).single;
    expect((fee['paidAmount'] as num).toDouble(), 500);
    expect(fee['status'], 'partial');

    await expectLater(ops.recordSchoolFeePayment(feeId: feeId, amount: 501), throwsStateError);
    fee = (await db.query('school_fees', where: 'id = ?', whereArgs: [feeId])).single;
    expect((fee['paidAmount'] as num).toDouble(), 500);
  });

  test('vehicle sale is one-way and contributes to per-vehicle profit report', () async {
    final vehicleId = await ops.addVehicleRecord(
      type: 'car',
      make: 'Toyota',
      model: 'Corolla',
      registrationNumber: 'ABC-123',
      purchasePrice: 40000,
    );

    await ops.recordVehicleTransaction(
      vehicleId: vehicleId,
      type: 'sale',
      partyName: 'Customer A',
      amount: 50000,
    );
    final reports = await ops.vehicleProfitReport();
    final row = reports.singleWhere((entry) => entry['vehicleId'] == vehicleId);
    expect((row['saleProceeds'] as num).toDouble(), 50000);
    expect((row['purchaseCost'] as num).toDouble(), 40000);
    expect((row['netProfit'] as num).toDouble(), 10000);

    await expectLater(
      ops.recordVehicleTransaction(vehicleId: vehicleId, type: 'sale', partyName: 'Customer B', amount: 51000),
      throwsStateError,
    );
  });

  test('cargo status changes retain timestamped history', () async {
    final cargoId = await ops.createCargoJob(
      customerName: 'Customer Cargo',
      loadDescription: 'Boxes',
      weight: 25,
      freightAmount: 2500,
    );
    await ops.updateCargoStatus(cargoId: cargoId, status: 'picked_up', location: 'Warehouse');
    await ops.updateCargoStatus(cargoId: cargoId, status: 'in_transit', location: 'Highway');

    final db = await DBService.instance.database;
    final job = (await db.query('cargo_jobs', where: 'id = ?', whereArgs: [cargoId])).single;
    final history = await db.query('cargo_status_history', where: 'cargoId = ?', whereArgs: [cargoId], orderBy: 'recordedAt');
    expect(job['status'], 'in_transit');
    expect(history, hasLength(2));
    expect(history.last['location'], 'Highway');
    expect(history.every((entry) => (entry['recordedAt'] as String).isNotEmpty), isTrue);
  });
}
