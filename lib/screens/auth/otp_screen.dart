import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../profile/shop_profile_screen.dart';

class OtpScreen extends StatefulWidget {
  final String phoneNumber;
  /// Only present because this build has no real SMS backend wired up yet —
  /// see AuthService docstring. Remove this param once a provider is connected.
  final String demoOtp;

  const OtpScreen({super.key, required this.phoneNumber, required this.demoOtp});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _otpController = TextEditingController();
  String? _error;

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Verify OTP')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Enter the 6-digit code sent to ${widget.phoneNumber}',
                style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Text(
                'Demo mode — no SMS provider connected yet. Your code: ${widget.demoOtp}',
                style: const TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, letterSpacing: 8),
              decoration: InputDecoration(
                counterText: '',
                errorText: _error,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                final ok = await auth.confirmOtp(widget.phoneNumber, _otpController.text.trim());
                if (!context.mounted) return;
                if (ok) {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const ShopProfileScreen(isFirstSetup: true)),
                    (route) => false,
                  );
                } else {
                  setState(() => _error = 'Incorrect code. Try again.');
                }
              },
              child: const Text('Verify & Continue'),
            ),
          ],
        ),
      ),
    );
  }
}
