class Product {
  final String id;
  String name;
  String category;
  int stockQuantity;
  double costPrice;
  double sellingPrice;
  int lowStockThreshold;

  Product({
    required this.id,
    required this.name,
    required this.category,
    required this.stockQuantity,
    required this.costPrice,
    required this.sellingPrice,
    this.lowStockThreshold = 5,
  });

  bool get isOutOfStock => stockQuantity <= 0;
  bool get isLowStock => stockQuantity > 0 && stockQuantity <= lowStockThreshold;
  double get margin => sellingPrice - costPrice;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'category': category,
        'stockQuantity': stockQuantity,
        'costPrice': costPrice,
        'sellingPrice': sellingPrice,
        'lowStockThreshold': lowStockThreshold,
      };

  factory Product.fromMap(Map<String, dynamic> map) => Product(
        id: map['id'] as String,
        name: map['name'] as String,
        category: (map['category'] as String?) ?? '',
        stockQuantity: (map['stockQuantity'] as num).toInt(),
        costPrice: (map['costPrice'] as num).toDouble(),
        sellingPrice: (map['sellingPrice'] as num).toDouble(),
        lowStockThreshold: (map['lowStockThreshold'] as num?)?.toInt() ?? 5,
      );
}
