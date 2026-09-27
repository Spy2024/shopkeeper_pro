class BillItem {
  final String productName;
  final int quantity;
  final double unitPrice;

  BillItem({required this.productName, required this.quantity, required this.unitPrice});

  double get lineTotal => quantity * unitPrice;

  Map<String, dynamic> toMap() => {
        'productName': productName,
        'quantity': quantity,
        'unitPrice': unitPrice,
      };

  factory BillItem.fromMap(Map<String, dynamic> map) => BillItem(
        productName: map['productName'] as String,
        quantity: map['quantity'] as int,
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
  });

  double get subtotal => items.fold(0.0, (sum, i) => sum + i.lineTotal);
  double get taxAmount => (subtotal - discount) * (taxPercent / 100);
  double get grandTotal => (subtotal - discount) + taxAmount;

  Map<String, dynamic> toMap() => {
        'id': id,
        'date': date.toIso8601String(),
        'customerName': customerName,
        'discount': discount,
        'taxPercent': taxPercent,
      };
}
