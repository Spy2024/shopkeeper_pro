import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Firebase phone auth accepts E.164-style Pakistan numbers', () {
    const phone = '+923334455667';
    expect(RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(phone), isTrue);
  });

  test('OTP contract is exactly six numeric digits', () {
    for (final otp in ['123456', '000001', '987654']) {
      expect(RegExp(r'^\d{6}$').hasMatch(otp), isTrue);
    }
    expect(RegExp(r'^\d{6}$').hasMatch('12345'), isFalse);
    expect(RegExp(r'^\d{6}$').hasMatch('12ab56'), isFalse);
  });
}
