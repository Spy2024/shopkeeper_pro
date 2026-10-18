import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Read-only web overview. Firestore rules remain the authorization boundary;
/// all queries are scoped to the current Firebase UID.
class WebDashboardScreen extends StatelessWidget {
  const WebDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: FirebaseAuth.instance.authStateChanges(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final user = snapshot.data;
      if (user == null) return const _WebSignInScreen();
      return _buildDashboard(context, user);
    },
  );

  Widget _buildDashboard(BuildContext context, User user) {
    final uid = user.uid;
    final db = FirebaseFirestore.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shopkeeper Pro · Web Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () async => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: FutureBuilder<List<QuerySnapshot<Map<String, dynamic>>>>(
        future: Future.wait([
          db.collection('users').doc(uid).collection('products').get(),
          db.collection('users').doc(uid).collection('bills').get(),
          db.collection('users').doc(uid).collection('customers').get(),
          db.collection('users').doc(uid).collection('expenses').get(),
        ]),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Dashboard data could not be loaded. Check Firebase configuration and Firestore rules.'));
          }
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final products = snapshot.data![0].docs;
          final bills = snapshot.data![1].docs;
          final customers = snapshot.data![2].docs;
          final expenses = snapshot.data![3].docs;
          double sumAmount(Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> rows, List<String> keys) {
            return rows.fold<double>(0, (sum, row) {
              for (final key in keys) {
                final value = row.data()[key];
                if (value is num) return sum + value.toDouble();
              }
              return sum;
            });
          }
          final sales = sumAmount(bills, ['total', 'grandTotal', 'totalAmount', 'amount']);
          final expenseTotal = sumAmount(expenses, ['amount', 'total', 'cost']);
          final lowStock = products.where((row) {
            final data = row.data();
            final qty = data['stockQuantity'];
            final threshold = data['lowStockThreshold'];
            return qty is num && threshold is num && qty <= threshold;
          }).length;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Business overview', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 6),
              Text('Signed in as ${user.phoneNumber ?? user.email ?? uid}', maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 20),
              Wrap(spacing: 12, runSpacing: 12, children: [
                _MetricCard(title: 'Products', value: '${products.length}', icon: Icons.inventory_2_outlined),
                _MetricCard(title: 'Bills', value: '${bills.length}', icon: Icons.receipt_long_outlined),
                _MetricCard(title: 'Customers', value: '${customers.length}', icon: Icons.people_outline),
                _MetricCard(title: 'Low stock', value: '$lowStock', icon: Icons.warning_amber_outlined),
                _MetricCard(title: 'Recorded sales', value: 'Rs. ${sales.toStringAsFixed(2)}', icon: Icons.trending_up),
                _MetricCard(title: 'Recorded expenses', value: 'Rs. ${expenseTotal.toStringAsFixed(2)}', icon: Icons.money_off),
              ]),
              const SizedBox(height: 24),
              Text('Recent bills', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (bills.isEmpty)
                const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No synced bills found yet.')))
              else
                ...bills.take(10).map((bill) {
                  final data = bill.data();
                  final amount = data['total'] ?? data['grandTotal'] ?? data['totalAmount'] ?? data['amount'] ?? '—';
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.receipt_long),
                      title: Text('Bill ${bill.id}'),
                      subtitle: Text('Date: ${data['date'] ?? data['createdAt'] ?? 'Unknown'}'),
                      trailing: Text('$amount'),
                    ),
                  );
                }),
              const SizedBox(height: 12),
              const Text('Read-only dashboard. All records shown are limited to the signed-in Firebase UID. Reports depend on the fields synced by the mobile app.'),
            ],
          );
        },
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.title, required this.value, required this.icon});
  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 240,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(icon, size: 28),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 4),
              Text(value, style: Theme.of(context).textTheme.titleLarge),
            ])),
          ],
        ),
      ),
    ),
  );
}

class _WebSignInScreen extends StatefulWidget {
  const _WebSignInScreen();

  @override
  State<_WebSignInScreen> createState() => _WebSignInScreenState();
}

class _WebSignInScreenState extends State<_WebSignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() { _busy = true; _error = null; });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
    } catch (_) {
      if (mounted) setState(() => _error = 'Sign-in failed. Check credentials and Firebase web configuration.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Shopkeeper Pro', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 8),
                const Text('Sign in to your secure web dashboard'),
                const SizedBox(height: 20),
                TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: _password, obscureText: true, onSubmitted: (_) => _signIn(), decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder())),
                if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _signIn,
                  child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Sign in'),
                ),
                const SizedBox(height: 8),
                const Text('Email/password sign-in must be enabled for this Firebase project.', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
