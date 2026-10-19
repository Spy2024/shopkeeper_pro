import 'dart:convert';

const mobileDeviceTypes = <String>{'new', 'used'};
const mobileDeviceStatuses = <String>{
  'inspection_pending',
  'in_stock',
  'reserved',
  'sold',
  'repair',
  'returned',
  'rejected',
  'written_off',
};
const mobileRepairStatuses = <String>{
  'received',
  'inspection',
  'estimate_sent',
  'awaiting_approval',
  'in_progress',
  'waiting_for_parts',
  'quality_check',
  'ready',
  'delivered',
  'cancelled',
  'rejected',
};

String normalizeImei(String? value) => (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');

void validateImeiPair(String? imei1, String? imei2) {
  final first = normalizeImei(imei1);
  final second = normalizeImei(imei2);
  for (final value in [first, second]) {
    if (value.isNotEmpty && (value.length < 14 || value.length > 16)) {
      throw ArgumentError('IMEI must contain 14 to 16 digits.');
    }
  }
  if (first.isNotEmpty && first == second) {
    throw ArgumentError('IMEI 1 and IMEI 2 must be different.');
  }
}

void validateNonNegativeMoney(Map<String, double> values) {
  for (final entry in values.entries) {
    if (!entry.value.isFinite || entry.value < 0) {
      throw ArgumentError('${entry.key} must be a finite amount of zero or more.');
    }
  }
}

class MobileDevice {
  final String id;
  final String deviceType;
  final String brand;
  final String model;
  final String? variant;
  final String? color;
  final String? imei1;
  final String? imei2;
  final String? serialNumber;
  final String? conditionGrade;
  final String status;
  final String? supplierId;
  final String? sellerName;
  final String? sellerPhone;
  final double purchasePrice;
  final double repairCost;
  final double sellingPrice;
  final int warrantyMonths;
  final DateTime? purchaseDate;
  final DateTime? soldAt;
  final String? soldBillId;
  final String? branchId;
  final Map<String, dynamic> inspection;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const MobileDevice({
    required this.id,
    required this.deviceType,
    required this.brand,
    required this.model,
    this.variant,
    this.color,
    this.imei1,
    this.imei2,
    this.serialNumber,
    this.conditionGrade,
    this.status = 'in_stock',
    this.supplierId,
    this.sellerName,
    this.sellerPhone,
    this.purchasePrice = 0,
    this.repairCost = 0,
    this.sellingPrice = 0,
    this.warrantyMonths = 0,
    this.purchaseDate,
    this.soldAt,
    this.soldBillId,
    this.branchId,
    this.inspection = const {},
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  double get totalKnownCost => purchasePrice + repairCost;
  double get expectedMargin => sellingPrice - totalKnownCost;

  Map<String, Object?> toMap() => {
    'id': id,
    'deviceType': deviceType,
    'brand': brand.trim(),
    'model': model.trim(),
    'variant': variant?.trim(),
    'color': color?.trim(),
    'imei1': normalizeImei(imei1).isEmpty ? null : normalizeImei(imei1),
    'imei2': normalizeImei(imei2).isEmpty ? null : normalizeImei(imei2),
    'serialNumber': serialNumber?.trim(),
    'conditionGrade': conditionGrade,
    'status': status,
    'supplierId': supplierId,
    'sellerName': sellerName?.trim(),
    'sellerPhone': sellerPhone?.trim(),
    'purchasePrice': purchasePrice,
    'repairCost': repairCost,
    'sellingPrice': sellingPrice,
    'warrantyMonths': warrantyMonths,
    'purchaseDate': purchaseDate?.toIso8601String(),
    'soldAt': soldAt?.toIso8601String(),
    'soldBillId': soldBillId,
    'branchId': branchId,
    'inspectionJson': jsonEncode(inspection),
    'notes': notes?.trim(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory MobileDevice.fromMap(Map<String, Object?> map) {
    DateTime? date(Object? value) =>
        value == null || value.toString().isEmpty ? null : DateTime.tryParse(value.toString());
    Map<String, dynamic> inspection;
    try {
      final decoded = jsonDecode((map['inspectionJson'] as String?) ?? '{}');
      inspection = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } on FormatException {
      inspection = <String, dynamic>{};
    }
    double number(Object? value) => (value as num?)?.toDouble() ?? 0;
    return MobileDevice(
      id: map['id'] as String,
      deviceType: (map['deviceType'] as String?) ?? 'new',
      brand: (map['brand'] as String?) ?? '',
      model: (map['model'] as String?) ?? '',
      variant: map['variant'] as String?,
      color: map['color'] as String?,
      imei1: map['imei1'] as String?,
      imei2: map['imei2'] as String?,
      serialNumber: map['serialNumber'] as String?,
      conditionGrade: map['conditionGrade'] as String?,
      status: (map['status'] as String?) ?? 'in_stock',
      supplierId: map['supplierId'] as String?,
      sellerName: map['sellerName'] as String?,
      sellerPhone: map['sellerPhone'] as String?,
      purchasePrice: number(map['purchasePrice']),
      repairCost: number(map['repairCost']),
      sellingPrice: number(map['sellingPrice']),
      warrantyMonths: (map['warrantyMonths'] as num?)?.toInt() ?? 0,
      purchaseDate: date(map['purchaseDate']),
      soldAt: date(map['soldAt']),
      soldBillId: map['soldBillId'] as String?,
      branchId: map['branchId'] as String?,
      inspection: inspection,
      notes: map['notes'] as String?,
      createdAt: date(map['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: date(map['updatedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class MobileRepairJob {
  final String id;
  final String jobNumber;
  final String customerName;
  final String? customerId;
  final String? customerPhone;
  final String? deviceId;
  final String? brand;
  final String? model;
  final String? imei;
  final String reportedIssue;
  final String? diagnosis;
  final double estimateAmount;
  final double approvedAmount;
  final double labourCharge;
  final double partsCost;
  final double advancePaid;
  final double balanceDue;
  final String status;
  final String? technicianName;
  final DateTime? promisedAt;
  final DateTime receivedAt;
  final DateTime? deliveredAt;
  final bool customerConsent;
  final int warrantyDays;
  final String? branchId;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const MobileRepairJob({
    required this.id,
    required this.jobNumber,
    required this.customerName,
    this.customerId,
    this.customerPhone,
    this.deviceId,
    this.brand,
    this.model,
    this.imei,
    required this.reportedIssue,
    this.diagnosis,
    this.estimateAmount = 0,
    this.approvedAmount = 0,
    this.labourCharge = 0,
    this.partsCost = 0,
    this.advancePaid = 0,
    this.balanceDue = 0,
    this.status = 'received',
    this.technicianName,
    this.promisedAt,
    required this.receivedAt,
    this.deliveredAt,
    this.customerConsent = false,
    this.warrantyDays = 0,
    this.branchId,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, Object?> toMap() => {
    'id': id,
    'jobNumber': jobNumber.trim(),
    'customerId': customerId,
    'customerName': customerName.trim(),
    'customerPhone': customerPhone?.trim(),
    'deviceId': deviceId,
    'brand': brand?.trim(),
    'model': model?.trim(),
    'imei': normalizeImei(imei).isEmpty ? null : normalizeImei(imei),
    'reportedIssue': reportedIssue.trim(),
    'diagnosis': diagnosis?.trim(),
    'estimateAmount': estimateAmount,
    'approvedAmount': approvedAmount,
    'labourCharge': labourCharge,
    'partsCost': partsCost,
    'advancePaid': advancePaid,
    'balanceDue': balanceDue,
    'status': status,
    'technicianName': technicianName?.trim(),
    'promisedAt': promisedAt?.toIso8601String(),
    'receivedAt': receivedAt.toIso8601String(),
    'deliveredAt': deliveredAt?.toIso8601String(),
    'customerConsent': customerConsent ? 1 : 0,
    'warrantyDays': warrantyDays,
    'branchId': branchId,
    'notes': notes?.trim(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory MobileRepairJob.fromMap(Map<String, Object?> map) {
    DateTime? date(Object? value) =>
        value == null || value.toString().isEmpty ? null : DateTime.tryParse(value.toString());
    double number(Object? value) => (value as num?)?.toDouble() ?? 0;
    return MobileRepairJob(
      id: map['id'] as String,
      jobNumber: (map['jobNumber'] as String?) ?? '',
      customerName: (map['customerName'] as String?) ?? '',
      customerId: map['customerId'] as String?,
      customerPhone: map['customerPhone'] as String?,
      deviceId: map['deviceId'] as String?,
      brand: map['brand'] as String?,
      model: map['model'] as String?,
      imei: map['imei'] as String?,
      reportedIssue: (map['reportedIssue'] as String?) ?? '',
      diagnosis: map['diagnosis'] as String?,
      estimateAmount: number(map['estimateAmount']),
      approvedAmount: number(map['approvedAmount']),
      labourCharge: number(map['labourCharge']),
      partsCost: number(map['partsCost']),
      advancePaid: number(map['advancePaid']),
      balanceDue: number(map['balanceDue']),
      status: (map['status'] as String?) ?? 'received',
      technicianName: map['technicianName'] as String?,
      promisedAt: date(map['promisedAt']),
      receivedAt: date(map['receivedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      deliveredAt: date(map['deliveredAt']),
      customerConsent: (map['customerConsent'] as num?)?.toInt() == 1,
      warrantyDays: (map['warrantyDays'] as num?)?.toInt() ?? 0,
      branchId: map['branchId'] as String?,
      notes: map['notes'] as String?,
      createdAt: date(map['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: date(map['updatedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
