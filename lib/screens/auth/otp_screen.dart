import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';

class OtpScreen extends StatefulWidget {
  final String phoneNumber;
  const OtpScreen({super.key, required this.phoneNumber});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _otpController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

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
                try {
                  final ok = await auth.confirmOtp(widget.phoneNumber, _otpController.text.trim());
                  if (!context.mounted) return;
                  if (ok) {
                    Navigator.popUntil(context, (route) => route.isFirst);
                  } else {
                    setState(() => _error = 'Incorrect code. Try again.');
                  }
                } catch (error) {
                  if (!context.mounted) return;
                  setState(() => _error = 'OTP verification failed: $error');
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
