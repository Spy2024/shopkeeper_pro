class DailySale {
  final String id;
  final DateTime date;
  final String productName;
  final double costPrice;
  final double salePrice;

  DailySale({
    required this.id,
    required this.date,
    required this.productName,
    required this.costPrice,
    required this.salePrice,
  });

  double get margin => salePrice - costPrice;

  Map<String, dynamic> toMap() => {
        'id': id,
        'date': date.toIso8601String(),
        'productName': productName,
        'costPrice': costPrice,
        'salePrice': salePrice,
      };

  factory DailySale.fromMap(Map<String, dynamic> map) => DailySale(
        id: map['id'] as String,
        date: DateTime.parse(map['date'] as String),
        productName: map['productName'] as String,
        costPrice: (map['costPrice'] as num).toDouble(),
        salePrice: (map['salePrice'] as num).toDouble(),
      );
}

class Expense {
  final String id;
  final DateTime date;
  final String label; // Rent, Electricity, Salaries, Misc...
  final double amount;

  Expense({required this.id, required this.date, required this.label, required this.amount});

  Map<String, dynamic> toMap() => {
        'id': id,
        'date': date.toIso8601String(),
        'label': label,
        'amount': amount,
      };

  factory Expense.fromMap(Map<String, dynamic> map) => Expense(
        id: map['id'] as String,
        date: DateTime.parse(map['date'] as String),
        label: map['label'] as String,
        amount: (map['amount'] as num).toDouble(),
      );
}
