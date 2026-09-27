class Supplier {
  final String id;
  String name;
  String phone;
  double totalStockReceivedValue;
  double totalPaymentsMade;

  Supplier({
    required this.id,
    required this.name,
    required this.phone,
    this.totalStockReceivedValue = 0,
    this.totalPaymentsMade = 0,
  });

  double get remainingBalance => totalStockReceivedValue - totalPaymentsMade;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'totalStockReceivedValue': totalStockReceivedValue,
        'totalPaymentsMade': totalPaymentsMade,
      };

  factory Supplier.fromMap(Map<String, dynamic> map) => Supplier(
        id: map['id'] as String,
        name: map['name'] as String,
        phone: map['phone'] as String,
        totalStockReceivedValue: (map['totalStockReceivedValue'] as num).toDouble(),
        totalPaymentsMade: (map['totalPaymentsMade'] as num).toDouble(),
      );
}

class SupplierOrderItem {
  final String productName;
  final int requiredQuantity;
  final double estimatedPrice;

  SupplierOrderItem({
    required this.productName,
    required this.requiredQuantity,
    required this.estimatedPrice,
  });

  double get estimatedTotal => requiredQuantity * estimatedPrice;
}

class SupplierOrder {
  final String id;
  final String supplierId;
  final String supplierName;
  final DateTime date;
  final List<SupplierOrderItem> items;
  String status; // draft, sent, received

  SupplierOrder({
    required this.id,
    required this.supplierId,
    required this.supplierName,
    required this.date,
    required this.items,
    this.status = 'draft',
  });

  double get estimatedOrderTotal => items.fold(0.0, (sum, i) => sum + i.estimatedTotal);
}
