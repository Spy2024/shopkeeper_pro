class Shop {
  final String id;
  String name;
  String address;
  String phone;
  String? taxNumber;
  String? logoPath;

  Shop({
    required this.id,
    required this.name,
    required this.address,
    required this.phone,
    this.taxNumber,
    this.logoPath,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'address': address,
        'phone': phone,
        'taxNumber': taxNumber,
        'logoPath': logoPath,
      };

  factory Shop.fromMap(Map<String, dynamic> map) => Shop(
        id: map['id'] as String,
        name: map['name'] as String,
        address: map['address'] as String,
        phone: map['phone'] as String,
        taxNumber: map['taxNumber'] as String?,
        logoPath: map['logoPath'] as String?,
      );
}
