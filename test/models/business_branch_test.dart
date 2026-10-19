import 'package:flutter_test/flutter_test.dart';
import 'package:shopkeeper_pro/models/business_branch.dart';

void main() {
  group('BusinessBranch', () {
    test('normalizes branch codes by trimming and uppercasing', () {
      expect(normalizeBranchCode('  wh-01 '), 'WH-01');
    });

    test('rejects codes outside the supported identifier format', () {
      for (final code in ['', 'A', 'branch with spaces', 'bad/code', '123456789012345678901']) {
        expect(() => normalizeBranchCode(code), throwsArgumentError, reason: 'code: $code');
      }
    });

    test('round-trips branch data and boolean flags', () {
      final createdAt = DateTime.utc(2026, 10, 11, 12, 30);
      final branch = BusinessBranch(
        id: 'branch-1',
        name: 'Main Branch',
        code: 'MAIN_01',
        address: 'Market Road',
        phone: '+923001234567',
        managerName: 'Store Manager',
        isMain: true,
        isActive: false,
        createdAt: createdAt,
      );

      final restored = BusinessBranch.fromMap(branch.toMap());

      expect(restored.id, branch.id);
      expect(restored.name, branch.name);
      expect(restored.code, branch.code);
      expect(restored.address, branch.address);
      expect(restored.phone, branch.phone);
      expect(restored.managerName, branch.managerName);
      expect(restored.isMain, isTrue);
      expect(restored.isActive, isFalse);
      expect(restored.createdAt, createdAt);
    });

    test('uses safe defaults for optional legacy map fields', () {
      final branch = BusinessBranch.fromMap({
        'id': 'legacy',
      });

      expect(branch.name, isEmpty);
      expect(branch.code, isEmpty);
      expect(branch.isMain, isFalse);
      expect(branch.isActive, isTrue);
      expect(branch.createdAt, DateTime.fromMillisecondsSinceEpoch(0));
    });
  });
}
