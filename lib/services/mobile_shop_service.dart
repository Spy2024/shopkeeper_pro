import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/mobile_device.dart';
import 'db_service.dart';
import 'sync_queue_service.dart';

class MobileShopService {
  MobileShopService._();
  static final MobileShopService instance = MobileShopService._();

  final Uuid _uuid = const Uuid();

  void _requireActiveAccount() {
    final userId = DBService.instance.activeUserId;
    if (userId == null || userId.trim().isEmpty) {
      throw StateError('Sign in before managing mobile devices or repair jobs.');
    }
  }

  Future<void> _queue({
    required String operation,
    required String table,
    required String id,
    required Map<String, Object?> data,
  }) async {
    try {
      await SyncQueueService.instance.queueOperation(
        operation: operation,
        tableName: table,
        documentId: id,
        data: Map<String, dynamic>.from(data),
      );
    } catch (error) {
      // Local SQLite is authoritative for offline work. Do not tell the user
      // that a saved intake/job failed merely because queuing sync did.
      debugPrint('[MobileShopService] Could not queue $table/$id; full sync can reconcile it: $error');
    }
  }

  Future<MobileDevice> createDevice({
    required String deviceType,
    required String brand,
    required String model,
    String? variant,
    String? color,
    String? imei1,
    String? imei2,
    String? serialNumber,
    String? conditionGrade,
    String? supplierId,
    String? sellerName,
    String? sellerPhone,
    double purchasePrice = 0,
    double repairCost = 0,
    double sellingPrice = 0,
    int warrantyMonths = 0,
    DateTime? purchaseDate,
    String? branchId,
    Map<String, dynamic> inspection = const {},
    String? notes,
  }) async {
    _requireActiveAccount();
    if (!mobileDeviceTypes.contains(deviceType)) {
      throw ArgumentError.value(deviceType, 'deviceType', 'Choose new or used.');
    }
    if (brand.trim().isEmpty || model.trim().isEmpty) {
      throw ArgumentError('Brand and model are required.');
    }
    validateImeiPair(imei1, imei2);
    validateNonNegativeMoney({
      'Purchase price': purchasePrice,
      'Repair cost': repairCost,
      'Selling price': sellingPrice,
    });
    if (warrantyMonths < 0) throw ArgumentError('Warranty months cannot be negative.');
    final firstImei = normalizeImei(imei1);
    final secondImei = normalizeImei(imei2);
    if (firstImei.isEmpty) throw ArgumentError('IMEI 1 is required for a mobile phone.');
    final cleanSerial = serialNumber?.trim();
    final now = DateTime.now();
    final device = MobileDevice(
      id: _uuid.v4(),
      deviceType: deviceType,
      brand: brand.trim(),
      model: model.trim(),
      variant: variant,
      color: color,
      imei1: firstImei.isEmpty ? null : firstImei,
      imei2: secondImei.isEmpty ? null : secondImei,
      serialNumber: cleanSerial?.isEmpty == true ? null : cleanSerial,
      conditionGrade: conditionGrade,
      status: deviceType == 'used' ? 'inspection_pending' : 'in_stock',
      supplierId: supplierId,
      sellerName: sellerName,
      sellerPhone: sellerPhone,
      purchasePrice: purchasePrice,
      repairCost: repairCost,
      sellingPrice: sellingPrice,
      warrantyMonths: warrantyMonths,
      purchaseDate: purchaseDate ?? now,
      branchId: branchId,
      inspection: Map<String, dynamic>.unmodifiable(inspection),
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );
    final row = device.toMap();
    final db = await DBService.instance.database;
    await db.transaction((txn) async {
      _requireActiveAccount();
      final identifiers = <String>[firstImei, secondImei]
          .where((value) => value.isNotEmpty).toSet().toList();
      if (identifiers.isNotEmpty) {
        final marks = List.filled(identifiers.length, '?').join(',');
        final existing = await txn.rawQuery(
          'SELECT id FROM mobile_devices WHERE imei1 IN ($marks) OR imei2 IN ($marks) LIMIT 1',
          [...identifiers, ...identifiers],
        );
        if (existing.isNotEmpty) {
          throw StateError('This IMEI is already registered to another device.');
        }
      }
      if (row['serialNumber'] != null) {
        final existing = await txn.query(
          'mobile_devices',
          columns: ['id'],
          where: 'serialNumber = ?',
          whereArgs: [row['serialNumber']],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          throw StateError('This serial number is already registered to another device.');
        }
      }
      await txn.insert('mobile_devices', row, conflictAlgorithm: ConflictAlgorithm.abort);
    });
    await _queue(operation: 'create', table: 'mobile_devices', id: device.id, data: row);
    return device;
  }

  Future<List<MobileDevice>> listDevices({
    String? deviceType,
    String? status,
    String? search,
  }) async {
    _requireActiveAccount();
    final db = await DBService.instance.database;
    final clauses = <String>[];
    final args = <Object?>[];
    if (deviceType != null) {
      if (!mobileDeviceTypes.contains(deviceType)) throw ArgumentError('Invalid device type.');
      clauses.add('deviceType = ?');
      args.add(deviceType);
    }
    if (status != null) {
      if (!mobileDeviceStatuses.contains(status)) throw ArgumentError('Invalid device status.');
      clauses.add('status = ?');
      args.add(status);
    }
    final cleanSearch = search?.trim();
    if (cleanSearch != null && cleanSearch.isNotEmpty) {
      clauses.add('(brand LIKE ? OR model LIKE ? OR imei1 LIKE ? OR imei2 LIKE ? OR serialNumber LIKE ?)');
      final query = '%$cleanSearch%';
      args.addAll([query, query, query, query, query]);
    }
    final rows = await db.query(
      'mobile_devices',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'createdAt DESC',
    );
    return rows.map((row) => MobileDevice.fromMap(row)).toList(growable: false);
  }

  Future<void> updateDeviceStatus(String deviceId, String status) async {
    _requireActiveAccount();
    if (!mobileDeviceStatuses.contains(status)) throw ArgumentError('Invalid device status.');
    if (status == 'sold' || status == 'returned') {
      throw StateError('Use the POS sale/return workflow to change a device to sold or returned.');
    }
    final db = await DBService.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      _requireActiveAccount();
      final rows = await txn.query('mobile_devices', where: 'id = ?', whereArgs: [deviceId], limit: 1);
      if (rows.isEmpty) throw StateError('Mobile device not found.');
      final current = MobileDevice.fromMap(rows.single);
      if (current.status == 'sold' && status != 'returned' && status != 'written_off') {
        throw StateError('A sold device cannot be moved back to stock without a return workflow.');
      }
      await txn.update('mobile_devices', {'status': status, 'updatedAt': now},
          where: 'id = ?', whereArgs: [deviceId]);
    });
    final rows = await db.query('mobile_devices', where: 'id = ?', whereArgs: [deviceId], limit: 1);
    await _queue(operation: 'update', table: 'mobile_devices', id: deviceId, data: rows.single);
  }

  Future<MobileRepairJob> createRepairJob({
    required String jobNumber,
    required String customerName,
    required String reportedIssue,
    String? customerId,
    String? customerPhone,
    String? deviceId,
    String? brand,
    String? model,
    String? imei,
    String? diagnosis,
    double estimateAmount = 0,
    double approvedAmount = 0,
    double labourCharge = 0,
    double partsCost = 0,
    double advancePaid = 0,
    String? technicianName,
    DateTime? promisedAt,
    bool customerConsent = false,
    int warrantyDays = 0,
    String? branchId,
    String? notes,
  }) async {
    _requireActiveAccount();
    if (jobNumber.trim().isEmpty || customerName.trim().isEmpty || reportedIssue.trim().isEmpty) {
      throw ArgumentError('Job number, customer name and reported issue are required.');
    }
    validateNonNegativeMoney({
      'Estimate': estimateAmount,
      'Approved amount': approvedAmount,
      'Labour charge': labourCharge,
      'Parts cost': partsCost,
      'Advance paid': advancePaid,
    });
    if (warrantyDays < 0) throw ArgumentError('Warranty days cannot be negative.');
    final cleanImei = normalizeImei(imei);
    if (cleanImei.isNotEmpty && (cleanImei.length < 14 || cleanImei.length > 16)) {
      throw ArgumentError('IMEI must contain 14 to 16 digits.');
    }
    final now = DateTime.now();
    final job = MobileRepairJob(
      id: _uuid.v4(),
      jobNumber: jobNumber.trim(),
      customerName: customerName.trim(),
      customerId: customerId,
      customerPhone: customerPhone,
      deviceId: deviceId,
      brand: brand,
      model: model,
      imei: cleanImei.isEmpty ? null : cleanImei,
      reportedIssue: reportedIssue.trim(),
      diagnosis: diagnosis,
      estimateAmount: estimateAmount,
      approvedAmount: approvedAmount,
      labourCharge: labourCharge,
      partsCost: partsCost,
      advancePaid: advancePaid,
      balanceDue: (approvedAmount - advancePaid).clamp(0.0, double.infinity).toDouble(),
      technicianName: technicianName,
      promisedAt: promisedAt,
      receivedAt: now,
      customerConsent: customerConsent,
      warrantyDays: warrantyDays,
      branchId: branchId,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );
    final row = job.toMap();
    final db = await DBService.instance.database;
    await db.transaction((txn) async {
      _requireActiveAccount();
      final duplicate = await txn.query('mobile_repair_jobs',
          columns: ['id'], where: 'jobNumber = ?', whereArgs: [job.jobNumber], limit: 1);
      if (duplicate.isNotEmpty) throw StateError('This repair job number already exists.');
      if (deviceId != null) {
        final device = await txn.query('mobile_devices', columns: ['id'], where: 'id = ?', whereArgs: [deviceId], limit: 1);
        if (device.isEmpty) throw StateError('Selected mobile device does not exist.');
      }
      await txn.insert('mobile_repair_jobs', row, conflictAlgorithm: ConflictAlgorithm.abort);
    });
    await _queue(operation: 'create', table: 'mobile_repair_jobs', id: job.id, data: row);
    return job;
  }

  Future<List<MobileRepairJob>> listRepairJobs({String? status, String? search}) async {
    _requireActiveAccount();
    final clauses = <String>[];
    final args = <Object?>[];
    if (status != null) {
      if (!mobileRepairStatuses.contains(status)) throw ArgumentError('Invalid repair status.');
      clauses.add('status = ?');
      args.add(status);
    }
    final cleanSearch = search?.trim();
    if (cleanSearch != null && cleanSearch.isNotEmpty) {
      clauses.add('(jobNumber LIKE ? OR customerName LIKE ? OR customerPhone LIKE ? OR imei LIKE ? OR model LIKE ?)');
      final query = '%$cleanSearch%';
      args.addAll([query, query, query, query, query]);
    }
    final rows = await (await DBService.instance.database).query(
      'mobile_repair_jobs',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'receivedAt DESC',
    );
    return rows.map((row) => MobileRepairJob.fromMap(row)).toList(growable: false);
  }

  Future<void> updateRepairJobStatus(String jobId, String status, {String? diagnosis}) async {
    _requireActiveAccount();
    if (!mobileRepairStatuses.contains(status)) throw ArgumentError('Invalid repair status.');
    final db = await DBService.instance.database;
    final rows = await db.query('mobile_repair_jobs', where: 'id = ?', whereArgs: [jobId], limit: 1);
    if (rows.isEmpty) throw StateError('Repair job not found.');
    final current = MobileRepairJob.fromMap(rows.single);
    if (status == 'in_progress' && !current.customerConsent) {
      throw StateError('Record customer approval before starting repair work.');
    }
    final now = DateTime.now();
    final changes = <String, Object?>{
      'status': status,
      'updatedAt': now.toIso8601String(),
      if (diagnosis != null) 'diagnosis': diagnosis.trim(),
      if (status == 'delivered') 'deliveredAt': now.toIso8601String(),
    };
    await db.update('mobile_repair_jobs', changes, where: 'id = ?', whereArgs: [jobId]);
    final updatedRows = await db.query('mobile_repair_jobs', where: 'id = ?', whereArgs: [jobId], limit: 1);
    await _queue(operation: 'update', table: 'mobile_repair_jobs', id: jobId, data: updatedRows.single);
  }
}
