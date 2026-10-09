import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/shop_provider.dart';
import '../../providers/sync_provider.dart';
import '../dashboard/home_screen.dart';
import '../profile/shop_profile_screen.dart';

class EmailAuthScreen extends StatefulWidget {
  const EmailAuthScreen({super.key});

  @override
  State<EmailAuthScreen> createState() => _EmailAuthScreenState();
}

class _EmailAuthScreenState extends State<EmailAuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _obscurePassword = true;
  bool _showVerificationAction = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    try {
      final verified = _register
          ? await auth.registerWithEmail(_email.text.trim(), _password.text)
          : await auth.signInWithEmail(_email.text.trim(), _password.text);
      if (!mounted) return;
      if (verified) {
        await _continueAfterAuth();
      } else {
        setState(() => _showVerificationAction = true);
      }
    } catch (_) {
      if (mounted) setState(() => _showVerificationAction = true);
    }
  }


  Future<void> _continueAfterAuth() async {
    final auth = context.read<AuthProvider>();
    final shopProvider = context.read<ShopProvider>();
    await shopProvider.load();
    if (!mounted) return;
    final uid = auth.userUid;
    if (uid != null && uid.isNotEmpty && auth.firebaseAvailable) {
      await context.read<SyncProvider>().init(uid);
    }
    if (!mounted) return;
    final Widget destination = shopProvider.shop == null
        ? const ShopProfileScreen(isFirstSetup: true)
        : const HomeScreen();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => destination),
      (route) => false,
    );
  }

  Future<void> _verifyEmail() async {
    final verified = await context.read<AuthProvider>().refreshEmailVerification();
    if (!mounted) return;
    if (verified) {
      await _continueAfterAuth();
    } else {
      setState(() => _showVerificationAction = true);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your email address first.')),
      );
      return;
    }
    try {
      await context.read<AuthProvider>().sendPasswordReset(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('If the account exists, a password reset email has been sent.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Email Account')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.mark_email_read_outlined,
                      size: 56, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    _register ? 'Create account' : 'Sign in with email',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Email address',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (value) {
                      final email = value?.trim() ?? '';
                      if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
                        return 'Enter a valid email address.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscurePassword,
                    autofillHints: _register
                        ? const [AutofillHints.newPassword]
                        : const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                      ),
                    ),
                    validator: (value) {
                      final password = value ?? '';
                      if (password.length < 8) return 'Use at least 8 characters.';
                      return null;
                    },
                  ),
                  if (auth.errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(auth.errorMessage!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: auth.isLoading ? null : _submit,
                    child: auth.isLoading
                        ? const SizedBox(height: 20, width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_register ? 'Create account and send verification' : 'Sign in'),
                  ),
                  if (!_register)
                    TextButton(
                      onPressed: auth.isLoading ? null : _resetPassword,
                      child: const Text('Forgot password?'),
                    ),
                  if (_showVerificationAction)
                    OutlinedButton.icon(
                      onPressed: auth.isLoading ? null : _verifyEmail,
                      icon: const Icon(Icons.verified_outlined),
                      label: const Text('I have verified my email'),
                    ),
                  TextButton(
                    onPressed: auth.isLoading
                        ? null
                        : () => setState(() {
                              _register = !_register;
                              _showVerificationAction = false;
                            }),
                    child: Text(_register
                        ? 'Already have an account? Sign in'
                        : 'New here? Create an account'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
