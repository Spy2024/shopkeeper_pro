import 'package:flutter_test/flutter_test.dart';
import 'package:shopkeeper_pro/services/auth_service.dart';

void main() {
  test('demo OTP accepts the generated code and rejects a wrong code', () async {
    const phone = '+923334455667';
    final otp = await AuthService.instance.sendOtp(phone);
    expect(RegExp(r'^\d{6}$').hasMatch(otp), isTrue);
    expect(AuthService.instance.verifyOtp(phone, '000000'), isFalse);
    expect(AuthService.instance.verifyOtp(phone, otp), isTrue);
  });
}
