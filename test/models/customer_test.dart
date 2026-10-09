import 'package:flutter_test/flutter_test.dart';
import 'package:shopkeeper_pro/models/customer.dart';

void main() {
  group('Customer model', () {
    test('round-trips local storage fields', () {
      final createdAt = DateTime(2026, 10, 9, 12, 30);
      final customer = Customer(
        id: 'customer-1',
        name: '  Ayesha Khan  ',
        phone: '03001234567',
        email: 'ayesha@example.com',
        notes: 'Regular customer',
        createdAt: createdAt,
      );

      final restored = Customer.fromMap(customer.toMap());
      expect(restored.id, 'customer-1');
      expect(restored.name, 'Ayesha Khan');
      expect(restored.phone, '03001234567');
      expect(restored.email, 'ayesha@example.com');
      expect(restored.notes, 'Regular customer');
      expect(restored.createdAt, createdAt);
      expect(customer.toMap()['name'], 'Ayesha Khan');
    });

    test('rejects empty id and empty name', () {
      expect(
        () => Customer(id: '', name: 'Name', createdAt: DateTime(2026)),
        throwsArgumentError,
      );
      expect(
        () => Customer(id: 'customer-2', name: ' ', createdAt: DateTime(2026)),
        throwsArgumentError,
      );
    });
  });
}
