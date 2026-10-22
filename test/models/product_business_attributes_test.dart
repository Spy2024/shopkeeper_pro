import 'package:flutter_test/flutter_test.dart';
import 'package:shopkeeper_pro/models/product.dart';

void main() {
  test('business-specific inventory attributes survive map round-trip', () {
    final product = Product(
      id: 'item-1',
      name: 'Cotton shirt',
      category: 'Clothing',
      stockQuantity: 4,
      costPrice: 500,
      sellingPrice: 750,
      businessAttributes: const {
        'Size': 'Large',
        'Colour': 'Blue',
        'Fabric / Material': 'Cotton',
      },
    );

    final restored = Product.fromMap(product.toMap());

    expect(restored.businessAttributes, product.businessAttributes);
    expect(restored.name, product.name);
    expect(restored.stockQuantity, product.stockQuantity);
  });

  test('legacy product maps without business attributes still load', () {
    final restored = Product.fromMap({
      'id': 'legacy-1',
      'name': 'Rice',
      'category': 'Grocery',
      'stockQuantity': 10,
      'costPrice': 100,
      'sellingPrice': 120,
    });

    expect(restored.businessAttributes, isEmpty);
  });
}
