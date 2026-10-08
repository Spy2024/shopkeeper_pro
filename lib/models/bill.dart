class BillItem {
  final String? productId;
  final String productName;
  final int quantity;
  final double unitPrice;

  BillItem({
    this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
  });

  double get lineTotal => quantity * unitPrice;

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'productName': productName,
        'quantity': quantity,
        'unitPrice': unitPrice,
      };

  factory BillItem.fromMap(Map<String, dynamic> map) => BillItem(
        productId: map['productId'] as String?,
        productName: map['productName'] as String,
        quantity: (map['quantity'] as num).toInt(),
        unitPrice: (map['unitPrice'] as num).toDouble(),
      );
}

class Bill {
  final String id;
  final DateTime date;
  final String? customerName;
  final List<BillItem> items;
  final double discount;
  final double taxPercent;

  Bill({
    required this.id,
    required this.date,
    this.customerName,
    required this.items,
    this.discount = 0,
    this.taxPercent = 0,
  })  : assert(discount >= 0),
        assert(taxPercent >= 0);

  double get subtotal => items.fold(0.0, (sum, i) => sum + i.lineTotal);
  double get taxableSubtotal => (subtotal - discount).clamp(0.0, double.infinity).toDouble();
  double get taxAmount => taxableSubtotal * (taxPercent / 100);
  double get grandTotal => taxableSubtotal + taxAmount;

  double refundFor(BillItem item, int quantity) {
    if (quantity <= 0 || quantity > item.quantity) {
      throw ArgumentError('Return quantity must be between 1 and the sold quantity.');
    }
    final discountRatio = subtotal <= 0 ? 0.0 : discount / subtotal;
    final discountedUnitPrice = item.unitPrice * (1 - discountRatio);
    return discountedUnitPrice * quantity * (1 + taxPercent / 100);
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'date': date.toIso8601String(),
        'customerName': customerName,
        'discount': discount,
        'taxPercent': taxPercent,
      };
}
