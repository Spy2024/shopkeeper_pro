class Product {
  final String id;
  String name;
  String category;
  int stockQuantity;
  double costPrice;
  double sellingPrice;
  int lowStockThreshold;
  String? barcode;
  DateTime? expiryDate;

  Product({
    required this.id,
    required this.name,
    required this.category,
    required this.stockQuantity,
    required this.costPrice,
    required this.sellingPrice,
    this.lowStockThreshold = 5,
    this.barcode,
    this.expiryDate,
  });

  bool get isOutOfStock => stockQuantity <= 0;
  bool get isLowStock => stockQuantity > 0 && stockQuantity <= lowStockThreshold;
  double get margin => sellingPrice - costPrice;
  bool get isExpired => expiryDate != null && _dateOnly(expiryDate!).isBefore(_dateOnly(DateTime.now()));
  bool get expiresWithin30Days => expiryDate != null && !isExpired &&
      !_dateOnly(expiryDate!).isAfter(_dateOnly(DateTime.now().add(const Duration(days: 30))));

  static DateTime _dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'category': category,
        'stockQuantity': stockQuantity,
        'costPrice': costPrice,
        'sellingPrice': sellingPrice,
        'lowStockThreshold': lowStockThreshold,
        'barcode': barcode,
        'expiryDate': expiryDate?.toIso8601String(),
      };

  factory Product.fromMap(Map<String, dynamic> map) => Product(
        id: map['id'] as String,
        name: map['name'] as String,
        category: (map['category'] as String?) ?? '',
        stockQuantity: (map['stockQuantity'] as num).toInt(),
        costPrice: (map['costPrice'] as num).toDouble(),
        sellingPrice: (map['sellingPrice'] as num).toDouble(),
        lowStockThreshold: (map['lowStockThreshold'] as num?)?.toInt() ?? 5,
        barcode: (map['barcode'] as String?)?.trim().isEmpty == true
            ? null
            : map['barcode'] as String?,
        expiryDate: (map['expiryDate'] as String?) == null ||
                (map['expiryDate'] as String).isEmpty
            ? null
            : DateTime.tryParse(map['expiryDate'] as String),
      );
}
