import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../profile/shop_profile_screen.dart';

class OtpScreen extends StatefulWidget {
  final String phoneNumber;
  const OtpScreen({super.key, required this.phoneNumber});
  @override State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _otpController = TextEditingController();
  String? _error;
  @override void dispose() { _otpController.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(appBar: AppBar(title: const Text('Verify OTP')), body: Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Enter the 6-digit code sent to ${widget.phoneNumber}', style: Theme.of(context).textTheme.bodyLarge),
      const SizedBox(height: 24),
      TextField(controller: _otpController, keyboardType: TextInputType.number, maxLength: 6, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, letterSpacing: 8), decoration: InputDecoration(counterText: '', errorText: _error)),
      const SizedBox(height: 16),
      SizedBox(width: double.infinity, child: ElevatedButton(onPressed: auth.isLoading ? null : () async { final code = _otpController.text.trim(); if (code.length != 6) { setState(() => _error = 'Enter the 6-digit OTP.'); return; } final ok = await context.read<AuthProvider>().confirmOtp(code); if (!context.mounted) return; if (ok) { Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const ShopProfileScreen(isFirstSetup: true)), (route) => false); } else { setState(() => _error = auth.errorMessage ?? 'Incorrect or expired code.'); } }, child: auth.isLoading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Verify & Continue'))),
    ])));
  }
}
