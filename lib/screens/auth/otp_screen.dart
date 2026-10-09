import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/shop_provider.dart';
import '../../providers/sync_provider.dart';
import '../dashboard/home_screen.dart';
import '../profile/shop_profile_screen.dart';

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
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Verify OTP')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Enter the 6-digit code sent to ${widget.phoneNumber}',
                style: Theme.of(context).textTheme.bodyLarge),
            if (!auth.firebaseAvailable && auth.demoOtp != null) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('Demo mode OTP: ${auth.demoOtp}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
            const SizedBox(height: 24),
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, letterSpacing: 8),
              decoration: InputDecoration(counterText: '', errorText: _error),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: auth.isLoading
                    ? null
                    : () async {
                        final code = _otpController.text.trim();
                        if (!RegExp(r'^\d{6}$').hasMatch(code)) {
                          setState(() => _error = 'Enter the 6-digit OTP.');
                          return;
                        }
                        final ok = await context
                            .read<AuthProvider>()
                            .confirmOtp(widget.phoneNumber, code);
                        if (!context.mounted) return;
                        if (ok) {
                          final authProvider = context.read<AuthProvider>();
                          final shopProvider = context.read<ShopProvider>();
                          await shopProvider.load();
                          if (!context.mounted) return;
                          final uid = authProvider.userUid;
                          if (uid != null && uid.isNotEmpty && authProvider.firebaseAvailable) {
                            await context.read<SyncProvider>().init(uid);
                          }
                          if (!context.mounted) return;
                          final Widget destination = shopProvider.shop == null
                              ? const ShopProfileScreen(isFirstSetup: true)
                              : const HomeScreen();
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(builder: (_) => destination),
                            (route) => false,
                          );
                        } else {
                          setState(() => _error =
                              context.read<AuthProvider>().errorMessage ??
                                  'Incorrect or expired code.');
                        }
                      },
                child: auth.isLoading
                    ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Verify & Continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
