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

  test('clinic, salon, agriculture and construction workflows persist linked records', () async {
    final patientId = await ops.addClinicPatient(name: 'Patient One', phone: '03000000000');
    final appointmentId = await ops.bookClinicAppointment(
      patientId: patientId,
      appointmentAt: '2026-10-22 10:00',
      clinician: 'Dr Test',
      reason: 'Consultation',
      fee: 1500,
    );
    await ops.recordClinicPayment(appointmentId: appointmentId, amount: 500);
    var db = await DBService.instance.database;
    var appointment = (await db.query(
      'clinic_appointments',
      where: 'id = ?',
      whereArgs: [appointmentId],
    )).single;
    expect((appointment['paidAmount'] as num).toDouble(), 500);
    await expectLater(
      ops.recordClinicPayment(appointmentId: appointmentId, amount: 1001),
      throwsStateError,
    );

    final serviceId = await ops.addSalonService(
      name: 'Haircut',
      durationMinutes: 30,
      price: 800,
    );
    final bookingId = await ops.bookSalonAppointment(
      customerName: 'Salon Customer',
      bookingAt: '2026-10-22 11:00',
      serviceId: serviceId,
      amount: 800,
    );
    await ops.updateSalonBookingStatus(bookingId: bookingId, status: 'completed');

    final plotId = await ops.addFarmPlot(
      name: 'North Plot',
      area: 2,
      crop: 'Wheat',
      season: 'Winter',
    );
    final activityId = await ops.recordFarmActivity(
      plotId: plotId,
      activityType: 'fertilizing',
      inputName: 'Fertilizer',
      quantity: 20,
      cost: 4500,
    );

    final projectId = await ops.addConstructionProject(
      name: 'House Build',
      clientName: 'Client One',
      budget: 100000,
    );
    final taskId = await ops.addConstructionTask(
      projectId: projectId,
      title: 'Foundation',
      assignedTo: 'Team A',
      cost: 12000,
    );
    await ops.updateConstructionTaskStatus(taskId: taskId, status: 'in_progress');

    db = await DBService.instance.database;
    expect(await db.query('clinic_appointments', where: 'id = ?', whereArgs: [appointmentId]), hasLength(1));
    expect(await db.query('salon_bookings', where: 'id = ?', whereArgs: [bookingId]), hasLength(1));
    expect(await db.query('farm_activities', where: 'id = ?', whereArgs: [activityId]), hasLength(1));
    expect(await db.query('construction_tasks', where: 'id = ?', whereArgs: [taskId]), hasLength(1));
    final project = (await db.query('construction_projects', where: 'id = ?', whereArgs: [projectId])).single;
    expect((project['spent'] as num).toDouble(), 12000);
    final report = await ops.businessVerticalReport();
    expect(((report['clinic'] as Map)['outstanding'] as num).toDouble(), 1000);
    expect(((report['salon'] as Map)['bookedValue'] as num).toDouble(), 800);
    expect(((report['agriculture'] as Map)['cost'] as num).toDouble(), 4500);
    expect(((report['construction'] as Map)['spent'] as num).toDouble(), 12000);
  });


  test('vehicle showroom records sale profit and prevents duplicate sale', () async {
    final vehicleId = await ops.addVehicleRecord(
      type: 'car',
      make: 'Test',
      model: 'Sedan',
      registrationNumber: 'ABC-123',
      purchasePrice: 100000,
    );
    await ops.recordVehicleTransaction(
      vehicleId: vehicleId,
      type: 'purchase',
      partyName: 'Seller',
      amount: 100000,
    );
    await ops.recordVehicleTransaction(
      vehicleId: vehicleId,
      type: 'expense',
      partyName: 'Workshop',
      amount: 5000,
      notes: 'Preparation',
    );
    await ops.recordVehicleTransaction(
      vehicleId: vehicleId,
      type: 'sale',
      partyName: 'Buyer',
      amount: 130000,
    );
    await expectLater(
      ops.recordVehicleTransaction(
        vehicleId: vehicleId,
        type: 'sale',
        partyName: 'Second Buyer',
        amount: 140000,
      ),
      throwsStateError,
    );

    final db = await DBService.instance.database;
    final vehicle = (await db.query(
      'vehicle_records',
      where: 'id = ?',
      whereArgs: [vehicleId],
    )).single;
    expect(vehicle['status'], 'sold');
    expect((vehicle['salePrice'] as num).toDouble(), 130000);
    expect(await db.query('vehicle_transactions', where: 'vehicleId = ?', whereArgs: [vehicleId]), hasLength(3));
    final reports = await ops.vehicleProfitReport();
    final report = reports.singleWhere((row) => row['vehicleId'] == vehicleId);
    expect((report['netProfit'] as num).toDouble(), 25000);
  });

  test('cargo tracking stores status history and passenger transport blocks duplicate seats', () async {
    final routeId = await ops.addTransportRoute(
      name: 'Karachi to Hyderabad',
      origin: 'Karachi',
      destination: 'Hyderabad',
    );
    final cargoId = await ops.createCargoJob(
      routeId: routeId,
      customerName: 'Cargo Customer',
      loadDescription: 'Boxes',
      weight: 120,
      freightAmount: 8500,
    );
    await ops.updateCargoStatus(
      cargoId: cargoId,
      status: 'picked_up',
      location: 'Karachi warehouse',
      note: 'Collected',
    );
    await ops.updateCargoStatus(
      cargoId: cargoId,
      status: 'in_transit',
      location: 'Super Highway',
    );
    final db = await DBService.instance.database;
    final cargo = (await db.query('cargo_jobs', where: 'id = ?', whereArgs: [cargoId])).single;
    expect(cargo['status'], 'in_transit');
    expect((cargo['trackingToken'] as String).length, greaterThan(30));
    expect(await db.query('cargo_status_history', where: 'cargoId = ?', whereArgs: [cargoId]), hasLength(2));
    await expectLater(
      ops.updateCargoStatus(cargoId: cargoId, status: 'unknown_status'),
      throwsArgumentError,
    );

    final ticketId = await ops.addTransportTicket(
      routeId: routeId,
      passengerName: 'Passenger One',
      travelDate: '2026-10-22',
      fare: 1200,
      seatNumber: 'A1',
    );
    expect(ticketId, isNotEmpty);
    await expectLater(
      ops.addTransportTicket(
        routeId: routeId,
        passengerName: 'Passenger Two',
        travelDate: '2026-10-22',
        fare: 1200,
        seatNumber: 'A1',
      ),
      throwsStateError,
    );
    expect(await db.query(
      'transport_tickets',
      where: 'routeId = ? AND travelDate = ? AND seatNumber = ?',
      whereArgs: [routeId, '2026-10-22', 'A1'],
    ), hasLength(1));
  });

}
