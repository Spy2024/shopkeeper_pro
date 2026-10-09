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
  }) {
    if (productName.trim().isEmpty) {
      throw ArgumentError.value(productName, 'productName', 'Cannot be empty.');
    }
    if (quantity <= 0) {
      throw ArgumentError.value(quantity, 'quantity', 'Must be positive.');
    }
    if (!unitPrice.isFinite || unitPrice < 0) {
      throw ArgumentError.value(unitPrice, 'unitPrice', 'Must be finite and non-negative.');
    }
  }

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
    required List<BillItem> items,
    this.discount = 0,
    this.taxPercent = 0,
  }) : items = List<BillItem>.unmodifiable(items) {
    if (id.trim().isEmpty) throw ArgumentError.value(id, 'id', 'Cannot be empty.');
    if (!discount.isFinite || discount < 0) {
      throw ArgumentError.value(discount, 'discount', 'Must be finite and non-negative.');
    }
    if (!taxPercent.isFinite || taxPercent < 0 || taxPercent > 100) {
      throw ArgumentError.value(taxPercent, 'taxPercent', 'Must be between 0 and 100.');
    }
  }

  double get subtotal => items.fold(0.0, (sum, i) => sum + i.lineTotal);
  double get taxableSubtotal => (subtotal - discount).clamp(0.0, double.infinity).toDouble();
  double get taxAmount => taxableSubtotal * (taxPercent / 100);
  double get grandTotal => taxableSubtotal + taxAmount;

  double refundFor(BillItem item, int quantity) {
    final belongsToBill = items.any((sold) =>
        sold.productId == item.productId &&
        sold.productName == item.productName &&
        sold.quantity == item.quantity &&
        sold.unitPrice == item.unitPrice);
    if (!belongsToBill) {
      throw ArgumentError('The returned item does not belong to this bill.');
    }
    if (quantity <= 0 || quantity > item.quantity) {
      throw ArgumentError('Return quantity must be between 1 and the sold quantity.');
    }
    final discountRatio =
        subtotal <= 0 ? 0.0 : (discount / subtotal).clamp(0.0, 1.0).toDouble();
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
