import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import 'otp_screen.dart';
import 'email_auth_screen.dart';

class PhoneEntryScreen extends StatefulWidget {
  final bool isRecovery;
  const PhoneEntryScreen({super.key, this.isRecovery = false});
  @override State<PhoneEntryScreen> createState() => _PhoneEntryScreenState();
}

class _PhoneEntryScreenState extends State<PhoneEntryScreen> {
  final _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  @override void dispose() { _phoneController.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(body: SafeArea(child: Padding(padding: const EdgeInsets.all(24), child: Form(key: _formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.storefront_rounded, size: 64, color: Theme.of(context).colorScheme.primary),
      const SizedBox(height: 16),
      Text(widget.isRecovery ? 'Recover Access' : 'Shopkeeper Pro', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('Enter your phone number to receive a secure SMS verification code.'),
      const SizedBox(height: 32),
      TextFormField(controller: _phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone Number', prefixIcon: Icon(Icons.phone_android), hintText: '+92 3XX XXXXXXX'), validator: (v) { final value = v?.trim() ?? ''; if (value.length < 8 || !value.startsWith('+')) return 'Use international phone format'; return null; }),
      const SizedBox(height: 24),
      if (auth.errorMessage != null) Text(auth.errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      const SizedBox(height: 12),
      SizedBox(width: double.infinity, child: ElevatedButton(onPressed: auth.isLoading ? null : () async { if (!_formKey.currentState!.validate()) return; final phone = _phoneController.text.trim(); try { await context.read<AuthProvider>().requestOtp(phone); if (!context.mounted) return; Navigator.push(context, MaterialPageRoute(builder: (_) => OtpScreen(phoneNumber: phone))); } catch (_) {} }, child: auth.isLoading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Send OTP'))),
      const SizedBox(height: 8),
      Center(child: TextButton(
        onPressed: auth.isLoading ? null : () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const EmailAuthScreen())),
        child: const Text('Use email instead'),
      )),
    ])))));
  }
}
