class Shop {
  final String id;
  String name;
  String address;
  String phone;
  String? taxNumber;
  String? email;
  String? website;
  String? facebookUrl;
  String? instagramUrl;
  String? socialUrl;
  String? logoPath;
  String businessType;

  Shop({
    required this.id,
    required this.name,
    required this.address,
    required this.phone,
    this.taxNumber,
    this.email,
    this.website,
    this.facebookUrl,
    this.instagramUrl,
    this.socialUrl,
    this.logoPath,
    this.businessType = 'general_retail',
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'address': address,
        'phone': phone,
        'taxNumber': taxNumber,
        'email': email,
        'website': website,
        'facebookUrl': facebookUrl,
        'instagramUrl': instagramUrl,
        'socialUrl': socialUrl,
        'logoPath': logoPath,
        'businessType': businessType,
      };

  factory Shop.fromMap(Map<String, dynamic> map) => Shop(
        id: map['id'] as String,
        name: map['name'] as String,
        address: (map['address'] as String?) ?? '',
        phone: (map['phone'] as String?) ?? '',
        taxNumber: map['taxNumber'] as String?,
        email: map['email'] as String?,
        website: map['website'] as String?,
        facebookUrl: map['facebookUrl'] as String?,
        instagramUrl: map['instagramUrl'] as String?,
        socialUrl: map['socialUrl'] as String?,
        logoPath: map['logoPath'] as String?,
        businessType: (map['businessType'] as String?) ?? 'general_retail',
      );
}
