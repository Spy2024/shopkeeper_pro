import 'package:flutter_test/flutter_test.dart';
import 'package:shopkeeper_pro/models/product.dart';

void main() {
  test('low stock classification is correct', () {
    final low = Product(id: '1', name: 'Tea', category: 'Grocery',
      stockQuantity: 3, costPrice: 50, sellingPrice: 70, lowStockThreshold: 5);
    final normal = Product(id: '2', name: 'Sugar', category: 'Grocery',
      stockQuantity: 20, costPrice: 50, sellingPrice: 70, lowStockThreshold: 5);
    final out = Product(id: '3', name: 'Milk', category: 'Grocery',
      stockQuantity: 0, costPrice: 50, sellingPrice: 70, lowStockThreshold: 5);
    expect(low.isLowStock, isTrue);
    expect(normal.isLowStock, isFalse);
    expect(out.isOutOfStock, isTrue);
  });
}
