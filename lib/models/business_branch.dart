class BusinessBranch {
  final String id;
  final String name;
  final String code;
  final String address;
  final String phone;
  final String managerName;
  final bool isMain;
  final bool isActive;
  final DateTime createdAt;

  const BusinessBranch({
    required this.id,
    required this.name,
    required this.code,
    this.address = '',
    this.phone = '',
    this.managerName = '',
    this.isMain = false,
    this.isActive = true,
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'code': code,
        'address': address,
        'phone': phone,
        'managerName': managerName,
        'isMain': isMain ? 1 : 0,
        'isActive': isActive ? 1 : 0,
        'createdAt': createdAt.toIso8601String(),
      };

  factory BusinessBranch.fromMap(Map<String, Object?> map) => BusinessBranch(
        id: map['id'] as String,
        name: (map['name'] as String?) ?? '',
        code: (map['code'] as String?) ?? '',
        address: (map['address'] as String?) ?? '',
        phone: (map['phone'] as String?) ?? '',
        managerName: (map['managerName'] as String?) ?? '',
        isMain: (map['isMain'] as num?)?.toInt() == 1,
        isActive: (map['isActive'] as num?)?.toInt() != 0,
        createdAt: DateTime.tryParse((map['createdAt'] as String?) ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}
