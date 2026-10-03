import 'package:flutter/material.dart';

void main() {
  runApp(const ShopkeeperProApp());
}

class ShopkeeperProApp extends StatelessWidget {
  const ShopkeeperProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shopkeeper Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green.shade700),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  static const List<Widget> screens = [
    DashboardScreen(),
    ProductsScreen(),
    SalesScreen(),
    CustomersScreen(),
    ReportsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shopkeeper Pro'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (value) {
          setState(() {
            _selectedIndex = value;
          });
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'Products'),
          NavigationDestination(icon: Icon(Icons.point_of_sale_outlined), label: 'Sales'),
          NavigationDestination(icon: Icon(Icons.people_alt_outlined), label: 'Customers'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), label: 'Reports'),
        ],
      ),
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final stats = [
      _StatCard(title: 'Today Sales', value: 'Rs. 28,500', color: Colors.green),
      _StatCard(title: 'Total Products', value: '148', color: Colors.blue),
      _StatCard(title: 'Customers', value: '96', color: Colors.orange),
      _StatCard(title: 'Low Stock', value: '12', color: Colors.red),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Overview',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                children: stats,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title, style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProductsScreen extends StatelessWidget {
  const ProductsScreen({super.key});

  final List<Map<String, String>> products = const [
    {'name': 'Rice 10kg', 'price': 'Rs. 950', 'stock': '32 bags'},
    {'name': 'Milk Pack', 'price': 'Rs. 120', 'stock': '45 packs'},
    {'name': 'Soap', 'price': 'Rs. 80', 'stock': '18 items'},
    {'name': 'Flour', 'price': 'Rs. 220', 'stock': '9 bags'},
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Products',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: products.length,
              itemBuilder: (context, index) {
                final product = products[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.inventory_2_rounded),
                    ),
                    title: Text(product['name'] ?? ''),
                    subtitle: Text('Available: ${product['stock']}'),
                    trailing: Text(product['price'] ?? ''),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class SalesScreen extends StatelessWidget {
  const SalesScreen({super.key});

  final List<Map<String, String>> sales = const [
    {'item': 'Rice', 'customer': 'Ali', 'amount': 'Rs. 1,250'},
    {'item': 'Soap', 'customer': 'Hassan', 'amount': 'Rs. 240'},
    {'item': 'Milk', 'customer': 'Zain', 'amount': 'Rs. 360'},
    {'item': 'Flour', 'customer': 'Usman', 'amount': 'Rs. 540'},
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sales',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: sales.length,
              itemBuilder: (context, index) {
                final sale = sales[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text(sale['item'] ?? ''),
                    subtitle: Text('Customer: ${sale['customer']}'),
                    trailing: Text(sale['amount'] ?? ''),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class CustomersScreen extends StatelessWidget {
  const CustomersScreen({super.key});

  final List<Map<String, String>> customers = const [
    {'name': 'Ali', 'phone': '+92 300 1234567', 'due': 'Rs. 1,200'},
    {'name': 'Hassan', 'phone': '+92 301 2345678', 'due': 'Rs. 850'},
    {'name': 'Zain', 'phone': '+92 302 3456789', 'due': 'Rs. 520'},
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Customers',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: customers.length,
              itemBuilder: (context, index) {
                final customer = customers[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(customer['name'] ?? ''),
                    subtitle: Text(customer['phone'] ?? ''),
                    trailing: Text(customer['due'] ?? ''),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Reports',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _ReportRow(label: 'Daily Sales', value: 'Rs. 28,500'),
          _ReportRow(label: 'Weekly Sales', value: 'Rs. 150,000'),
          _ReportRow(label: 'Monthly Sales', value: 'Rs. 620,000'),
          _ReportRow(label: 'Profit', value: 'Rs. 180,000'),
        ],
      ),
    );
  }
}

class _ReportRow extends StatelessWidget {
  final String label;
  final String value;

  const _ReportRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(label),
        trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}
