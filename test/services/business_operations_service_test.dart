import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shopkeeper_pro/services/db_service.dart';
import 'package:shopkeeper_pro/services/business_operations_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final operations = BusinessOperationsService.instance;
  final dbService = DBService.instance;
  String userId() => 'business_test_${DateTime.now().microsecondsSinceEpoch}';

  tearDown(() async {
    await dbService.clearActiveUser();
  });

  test('each authenticated user receives a separate SQLite database', () async {
    final firstUser = userId();
    await dbService.configureForUser(firstUser);
    final firstDb = await dbService.database;
    await firstDb.insert('products', {
      'id': 'private-product',
      'name': 'Private tea',
      'category': 'grocery',
      'stockQuantity': 9,
      'costPrice': 1,
      'sellingPrice': 2,
      'lowStockThreshold': 2,
    });

    await dbService.configureForUser(userId());
    final secondDb = await dbService.database;
    expect(await secondDb.query('products', where: 'id = ?', whereArgs: ['private-product']), isEmpty);

    await dbService.configureForUser(firstUser);
    final restoredDb = await dbService.database;
    expect(await restoredDb.query('products', where: 'id = ?', whereArgs: ['private-product']), hasLength(1));
  });

  test('customer ledger calculates outstanding balance', () async {
    await dbService.configureForUser(userId());
    final customerId = await operations.addCustomer(name: 'Test Customer');
    await operations.recordCustomerLedgerEntry(
      customerId: customerId, type: 'credit', amount: 1250, note: 'Sale on credit');
    await operations.recordCustomerLedgerEntry(
      customerId: customerId, type: 'payment', amount: 400, note: 'Cash received');
    expect(await operations.customerBalance(customerId), 850);
  });

  test('split payment rejects mismatched total and stores valid tenders', () async {
    await dbService.configureForUser(userId());
    final db = await dbService.database;
    await db.insert('bills', {
      'id': 'bill-split', 'date': DateTime.now().toIso8601String(),
      'customerName': null, 'discount': 0, 'taxPercent': 0,
    });
    await db.insert('bill_items', {
      'billId': 'bill-split', 'productName': 'Test item',
      'quantity': 1, 'unitPrice': 1000,
    });

    await expectLater(
      operations.recordSplitPayment(
        billId: 'bill-split',
        billTotal: 1000,
        payments: const [PaymentLine(method: 'cash', amount: 500)],
      ),
      throwsStateError,
    );
    await operations.recordSplitPayment(
      billId: 'bill-split',
      billTotal: 1000,
      payments: const [
        PaymentLine(method: 'cash', amount: 400),
        PaymentLine(method: 'card', amount: 600),
      ],
    );
    expect(await db.query('payments', where: 'billId = ?', whereArgs: ['bill-split']), hasLength(2));
  });

  test('return restores stock atomically and cannot return more than sold', () async {
    await dbService.configureForUser(userId());
    final db = await dbService.database;
    await db.insert('products', {
      'id': 'product-1', 'name': 'Rice', 'category': 'grocery',
      'stockQuantity': 3, 'costPrice': 10, 'sellingPrice': 15, 'lowStockThreshold': 2,
    });
    await db.insert('bills', {
      'id': 'bill-return', 'date': DateTime.now().toIso8601String(),
      'customerName': 'Test Customer', 'discount': 0, 'taxPercent': 0,
    });
    await db.insert('bill_items', {
      'billId': 'bill-return', 'productName': 'Rice', 'quantity': 2, 'unitPrice': 15,
    });

    await operations.processReturn(
      billId: 'bill-return',
      items: const [ReturnLine(productId: 'product-1', productName: 'Rice', quantity: 1, unitPrice: 15)],
      refundAmount: 15,
      customerName: 'Test Customer',
    );
    final stock = await db.query('products', columns: ['stockQuantity'], where: 'id = ?', whereArgs: ['product-1']);
    expect(stock.single['stockQuantity'], 4);

    await expectLater(
      operations.processReturn(
        billId: 'bill-return',
        items: const [ReturnLine(productId: 'product-1', productName: 'Rice', quantity: 2, unitPrice: 15)],
        refundAmount: 30,
      ),
      throwsStateError,
    );
    final returns = await db.query('returns', where: 'billId = ?', whereArgs: ['bill-return']);
    expect(returns, hasLength(1));
  });

  test('return restores stock to the branch that made the sale', () async {
    await dbService.configureForUser(userId());
    final db = await dbService.database;
    await db.insert('products', {
      'id': 'branch-return-product', 'name': 'Branch Water', 'category': 'grocery',
      'stockQuantity': 100, 'costPrice': 10, 'sellingPrice': 15, 'lowStockThreshold': 5,
    });
    final branchId = await operations.createBranch(name: 'Return Branch');
    await operations.setBranchStock(branchId: branchId, productId: 'branch-return-product', quantity: 5);
    await db.insert('bills', {
      'id': 'branch-return-bill', 'date': DateTime.now().toIso8601String(),
      'customerName': 'Customer', 'discount': 0, 'taxPercent': 0, 'branchId': branchId,
    });
    await db.insert('bill_items', {
      'billId': 'branch-return-bill', 'productName': 'Branch Water', 'quantity': 2, 'unitPrice': 15,
    });

    await operations.processReturn(
      billId: 'branch-return-bill',
      items: const [ReturnLine(productId: 'branch-return-product', productName: 'Branch Water', quantity: 1, unitPrice: 15)],
      refundAmount: 15,
    );

    final branchRows = await db.query('branch_stock',
        where: 'branchId = ? AND productId = ?', whereArgs: [branchId, 'branch-return-product']);
    final productRows = await db.query('products', where: 'id = ?', whereArgs: ['branch-return-product']);
    expect(branchRows.single['quantity'], 6);
    expect(productRows.single['stockQuantity'], 100);
  });

  test('spare part compatibility validates type and year range', () async {
    await dbService.configureForUser(userId());
    final db = await dbService.database;
    await db.insert('products', {
      'id': 'brake-pad', 'name': 'Brake Pad', 'category': 'spare-parts',
      'stockQuantity': 20, 'costPrice': 100, 'sellingPrice': 150, 'lowStockThreshold': 3,
    });
    final id = await operations.addSparePartCompatibility(
      productId: 'brake-pad', partType: 'car', make: 'Toyota',
      model: 'Corolla', yearFrom: 2018, yearTo: 2024,
    );
    final rows = await db.query('spare_part_compatibility', where: 'id = ?', whereArgs: [id]);
    expect(rows.single['make'], 'Toyota');
    await expectLater(
      operations.addSparePartCompatibility(productId: 'brake-pad', partType: 'car', yearFrom: 2025, yearTo: 2020),
      throwsArgumentError,
    );
  });

  test('restaurant menu order totals and kitchen state gate order completion', () async {
    await dbService.configureForUser(userId());
    final tableId = await operations.createRestaurantTable(name: 'T-1', capacity: 4);
    final orderId = await operations.createRestaurantOrder(tableId: tableId);
    final menuId = await operations.addRestaurantMenuItem(name: 'Biryani', category: 'Main', price: 450);
    final itemId = await operations.addRestaurantOrderItem(orderId: orderId, menuItemId: menuId, quantity: 2);
    var db = await dbService.database;
    expect((await db.query('restaurant_orders', where: 'id = ?', whereArgs: [orderId])).single['total'], 900);
    await expectLater(operations.completeRestaurantOrder(orderId), throwsStateError);
    await operations.updateKitchenStatus(orderItemId: itemId, status: 'preparing');
    await operations.updateKitchenStatus(orderItemId: itemId, status: 'served');
    await expectLater(operations.completeRestaurantOrder(orderId), throwsStateError);
    await expectLater(
      operations.recordRestaurantPayment(
        orderId: orderId,
        payments: const [PaymentLine(method: 'cash', amount: 800)],
      ),
      throwsStateError,
    );
    await operations.recordRestaurantPayment(
      orderId: orderId,
      payments: const [
        PaymentLine(method: 'cash', amount: 500),
        PaymentLine(method: 'card', amount: 400),
      ],
    );
    await expectLater(
      operations.recordRestaurantPayment(
        orderId: orderId,
        payments: const [PaymentLine(method: 'cash', amount: 900)],
      ),
      throwsStateError,
    );
    await operations.completeRestaurantOrder(orderId);
    expect((await db.query('restaurant_order_payments', where: 'orderId = ?', whereArgs: [orderId])), hasLength(2));
    expect((await db.query('restaurant_orders', where: 'id = ?', whereArgs: [orderId])).single['status'], 'completed');
    expect((await db.query('restaurant_tables', where: 'id = ?', whereArgs: [tableId])).single['status'], 'available');
  });

  test('cargo status updates keep a traceable location history', () async {
    await dbService.configureForUser(userId());
    final cargoId = await operations.createCargoJob(customerName: 'Cargo Customer', weight: 10, freightAmount: 500);
    await operations.updateCargoStatus(cargoId: cargoId, status: 'picked_up', location: 'Karachi warehouse');
    await operations.updateCargoStatus(cargoId: cargoId, status: 'in_transit', location: 'Hyderabad');
    final db = await dbService.database;
    final cargo = (await db.query('cargo_jobs', where: 'id = ?', whereArgs: [cargoId])).single;
    final history = await db.query('cargo_status_history', where: 'cargoId = ?', whereArgs: [cargoId], orderBy: 'recordedAt ASC');
    expect(cargo['status'], 'in_transit');
    expect(history, hasLength(2));
    expect(history.last['location'], 'Hyderabad');
  });

  test('vehicle ledger calculates sale less purchase and expenses', () async {
    await dbService.configureForUser(userId());
    final vehicleId = await operations.addVehicleRecord(
      type: 'car', make: 'Toyota', model: 'Corolla', purchasePrice: 1000000,
    );
    await operations.recordVehicleTransaction(
      vehicleId: vehicleId, type: 'purchase', partyName: 'Vendor', amount: 1000000,
    );
    await operations.recordVehicleTransaction(
      vehicleId: vehicleId, type: 'expense', partyName: 'Workshop', amount: 25000,
    );
    await operations.recordVehicleTransaction(
      vehicleId: vehicleId, type: 'sale', partyName: 'Buyer', amount: 1200000,
    );
    final db = await dbService.database;
    expect((await db.query('vehicle_records', where: 'id = ?', whereArgs: [vehicleId])).single['status'], 'sold');
    await expectLater(
      operations.recordVehicleTransaction(vehicleId: vehicleId, type: 'sale', partyName: 'Second buyer', amount: 1250000),
      throwsStateError,
    );
    final report = (await operations.vehicleProfitReport()).single;
    expect(report['saleProceeds'], 1200000);
    expect(report['purchaseCost'], 1000000);
    expect(report['expenses'], 25000);
    expect(report['netProfit'], 175000);
    expect(await db.query('expenses'), hasLength(2));
    expect(await db.query('daily_sales'), hasLength(1));
  });

  test('school clinic salon farm construction and public service records persist', () async {
    await dbService.configureForUser(userId());
    final student = await operations.addSchoolStudent(name: 'Student A', className: 'Grade 4');
    await operations.addSchoolFee(studentId: student, amount: 2000, paidAmount: 500);
    final patient = await operations.addClinicPatient(name: 'Patient A');
    await operations.bookClinicAppointment(patientId: patient, appointmentAt: '2026-10-19T10:00:00', fee: 800);
    await operations.addSalonService(name: 'Haircut', durationMinutes: 30, price: 300);
    final plot = await operations.addFarmPlot(name: 'Plot A', area: 2, crop: 'Wheat');
    await operations.recordFarmActivity(plotId: plot, activityType: 'fertilizer', quantity: 4, cost: 2500);
    final project = await operations.addConstructionProject(name: 'House', budget: 1000000);
    await operations.addConstructionTask(projectId: project, title: 'Foundation', cost: 50000);
    await operations.addPublicServiceCase(caseNumber: 'PS-100', applicantName: 'Applicant', serviceType: 'Certificate', fee: 100);
    final db = await dbService.database;
    expect(await db.query('school_students'), hasLength(1));
    expect(await db.query('school_fees'), hasLength(1));
    expect(await db.query('clinic_appointments'), hasLength(1));
    expect(await db.query('salon_services'), hasLength(1));
    expect(await db.query('farm_activities'), hasLength(1));
    expect((await db.query('construction_projects')).single['spent'], 50000);
    expect(await db.query('public_service_cases'), hasLength(1));
  });

  test('branch report combines stock units and cash in/out', () async {
    await dbService.configureForUser(userId());
    final db = await dbService.database;
    final branchId = await operations.createBranch(name: 'Main Branch');
    await db.insert('products', {
      'id': 'branch-product', 'name': 'Sugar', 'category': 'grocery',
      'stockQuantity': 30, 'costPrice': 1, 'sellingPrice': 2, 'lowStockThreshold': 5,
    });
    await operations.setBranchStock(branchId: branchId, productId: 'branch-product', quantity: 24);
    await operations.recordBranchCash(branchId: branchId, type: 'in', amount: 5000);
    await operations.recordBranchCash(branchId: branchId, type: 'out', amount: 750);

    final report = await operations.branchReport(branchId);
    expect(report['stockUnits'], 24);
    expect(report['cashBalance'], 4250);
  });

  test('vertical payments, lifecycle transitions and reports validate balances', () async {
    await dbService.configureForUser(userId());
    final student = await operations.addSchoolStudent(name: 'Fee Student');
    final feeId = await operations.addSchoolFee(studentId: student, amount: 2000, paidAmount: 500);
    await operations.recordSchoolFeePayment(feeId: feeId, amount: 1500);
    await expectLater(operations.recordSchoolFeePayment(feeId: feeId, amount: 1), throwsStateError);

    final patient = await operations.addClinicPatient(name: 'Lifecycle Patient');
    final appointmentId = await operations.bookClinicAppointment(
      patientId: patient, appointmentAt: '2026-10-20T10:00:00', fee: 800,
    );
    await operations.recordClinicPayment(appointmentId: appointmentId, amount: 300);
    await expectLater(operations.recordClinicPayment(appointmentId: appointmentId, amount: 600), throwsStateError);
    await operations.updateClinicAppointmentStatus(appointmentId: appointmentId, status: 'checked_in');

    final salonService = await operations.addSalonService(name: 'Wash', durationMinutes: 20, price: 200);
    await operations.bookSalonAppointment(customerName: 'Salon customer', bookingAt: '2026-10-20T11:00:00', serviceId: salonService, amount: 200);
    final db = await dbService.database;
    final booking = (await db.query('salon_bookings')).single;
    await operations.updateSalonBookingStatus(bookingId: booking['id']! as String, status: 'in_progress');

    final project = await operations.addConstructionProject(name: 'Report project', budget: 10000);
    await operations.addConstructionTask(projectId: project, title: 'Task A', cost: 2500);
    final task = (await db.query('construction_tasks')).single;
    await operations.updateConstructionTaskStatus(taskId: task['id']! as String, status: 'in_progress');

    final caseId = await operations.addPublicServiceCase(caseNumber: 'CASE-TEST', applicantName: 'Applicant', serviceType: 'Permit', fee: 100);
    await operations.updatePublicServiceCaseStatus(caseId: caseId, status: 'in_progress');

    final report = await operations.businessVerticalReport();
    expect((report['school'] as Map)['outstanding'], 0);
    expect((report['clinic'] as Map)['outstanding'], 500);
    expect((report['construction'] as Map)['spent'], 2500);
    expect((report['publicServices'] as Map)['fees'], 100);
  });
}
