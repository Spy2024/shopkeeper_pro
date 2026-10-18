import 'package:flutter/material.dart';
import '../pos/pos_screen.dart';
import '../inventory/inventory_screen.dart';
import '../supplier/supplier_screen.dart';
import '../customers/customers_screen.dart';
import '../sales/daily_sales_screen.dart';
import 'financial_dashboard_screen.dart';
import 'branch_reports_screen.dart';
import 'business_center_screen.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  late final List<Widget> _screens = [
    BusinessCenterScreen(onOpenModule: _openModule),
    const PosScreen(),
    const CustomersScreen(),
    const InventoryScreen(),
    const DailySalesScreen(),
    const SupplierScreen(),
    const FinancialDashboardScreen(),
    const BranchReportsScreen(),
    const SettingsScreen(),
  ];

  void _openModule(int index) {
    if (index < 0 || index >= _screens.length) return;
    setState(() => _index = index);
  }

  int get _navigationIndex {
    if (_index == 0) return 0;
    if (_index == 1) return 1;
    if (_index == 3) return 2;
    if (_index == 4) return 3;
    return 4;
  }

  void _selectNavigation(int selected) {
    switch (selected) {
      case 0:
        _openModule(0);
      case 1:
        _openModule(1);
      case 2:
        _openModule(3);
      case 3:
        _openModule(4);
      case 4:
        _showMoreModules();
    }
  }

  Future<void> _showMoreModules() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('More modules', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 12),
              _MoreModuleTile(icon: Icons.people_outline, title: 'Customers', index: 2),
              _MoreModuleTile(icon: Icons.handshake_outlined, title: 'Suppliers', index: 5),
              _MoreModuleTile(icon: Icons.account_balance_wallet_outlined, title: 'Finance', index: 6),
              _MoreModuleTile(icon: Icons.assessment_outlined, title: 'Branch reports', index: 7),
              _MoreModuleTile(icon: Icons.settings_outlined, title: 'Settings', index: 8),
            ],
          ),
        ),
      ),
    );
    if (selected != null && mounted) _openModule(selected);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navigationIndex,
        onDestinationSelected: _selectNavigation,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Business'),
          NavigationDestination(icon: Icon(Icons.point_of_sale_outlined), selectedIcon: Icon(Icons.point_of_sale), label: 'Billing'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Inventory'),
          NavigationDestination(icon: Icon(Icons.trending_up_outlined), selectedIcon: Icon(Icons.trending_up), label: 'Sales'),
          NavigationDestination(icon: Icon(Icons.grid_view_rounded), selectedIcon: Icon(Icons.grid_view_rounded), label: 'More'),
        ],
      ),
    );
  }
}

class _MoreModuleTile extends StatelessWidget {
  const _MoreModuleTile({required this.icon, required this.title, required this.index});

  final IconData icon;
  final String title;
  final int index;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: () => Navigator.of(context).pop(index),
  );
}
