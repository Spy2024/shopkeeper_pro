import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import 'otp_screen.dart';

class PhoneEntryScreen extends StatefulWidget {
  final bool isRecovery;
  const PhoneEntryScreen({super.key, this.isRecovery = false});

  @override
  State<PhoneEntryScreen> createState() => _PhoneEntryScreenState();
}

class _PhoneEntryScreenState extends State<PhoneEntryScreen> {
  final _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.storefront_rounded, size: 64, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text(widget.isRecovery ? 'Recover Access' : 'Shopkeeper Pro',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  widget.isRecovery
                      ? 'Enter your registered phone number to receive a recovery code.'
                      : 'Manage billing, inventory, suppliers and profit — all offline after sign-in.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Phone Number',
                    prefixIcon: const Icon(Icons.phone_android),
                    hintText: '+92 3XX XXXXXXX',
                    errorText: _error,
                  ),
                  validator: (v) =>
                      (v == null || v.trim().length < 8) ? 'Enter a valid phone number' : null,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: auth.isLoading
                        ? null
                        : () async {
                            if (!_formKey.currentState!.validate()) return;
                            setState(() => _error = null);
                            try {
                              await auth.requestOtp(_phoneController.text.trim());
                              if (!context.mounted) return;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => OtpScreen(
                                    phoneNumber: _phoneController.text.trim(),
                                  ),
                                ),
                              );
                            } catch (e) {
                              if (mounted) setState(() => _error = e.toString());
                            }
                          },
                    child: auth.isLoading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Send OTP'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
