import 'package:flutter/material.dart';
import '../../utils/theme.dart';

class BusinessCenterScreen extends StatefulWidget {
  const BusinessCenterScreen({super.key, required this.onOpenModule});

  /// Opens an existing app area by its HomeScreen navigation index.
  final ValueChanged<int> onOpenModule;

  @override
  State<BusinessCenterScreen> createState() => _BusinessCenterScreenState();
}

class _BusinessCenterScreenState extends State<BusinessCenterScreen> {
  final TextEditingController _search = TextEditingController();
  String _selectedCategory = 'General Store';

  static const _categories = <_BusinessCategory>[
    _BusinessCategory('General Store', 'Retail, karyana, supermarket', Icons.shopping_basket_outlined, ['POS Billing', 'Inventory', 'Purchases', 'Customers', 'Suppliers', 'Finance', 'Reports']),
    _BusinessCategory('Wholesale', 'Distribution and bulk sales', Icons.warehouse_outlined, ['Bulk Pricing', 'Inventory', 'Purchase Receiving', 'Customer Ledger', 'Supplier Ledger', 'Reports']),
    _BusinessCategory('Mobile Shop', 'New, used phones and repair', Icons.smartphone_outlined, ['IMEI Device Stock', 'Mobile POS', 'Device Intake', 'Repair Jobs', 'Spare Parts', 'Warranty Claims', 'Returns & Refunds']),
    _BusinessCategory('Electronics', 'Electronics and appliances', Icons.devices_other, ['Serial Numbers', 'Inventory', 'Warranty', 'Purchases', 'POS Billing', 'Reports']),
    _BusinessCategory('Spare Parts', 'Bike, car, mobile and other parts', Icons.build, ['Part Catalog', 'Compatible Models', 'Inventory', 'Workshop Jobs', 'Purchases', 'Warranty']),
    _BusinessCategory('Clothing', 'Garments, shoes and fashion', Icons.checkroom_outlined, ['Size & Color Variants', 'Inventory', 'POS Billing', 'Purchases', 'Returns', 'Reports']),
    _BusinessCategory('Carpet & Furniture', 'Carpet, furniture and crockery', Icons.chair_outlined, ['Catalog', 'Measurements', 'Orders', 'Inventory', 'Delivery', 'Finance']),
    _BusinessCategory('Restaurant', 'Hotel, cafe, bakery and food', Icons.restaurant_outlined, ['Menu & Recipes', 'Table Orders', 'Kitchen Tickets', 'Ingredient Stock', 'Purchases', 'Daily Closing']),
    _BusinessCategory('Snooker Club', 'Snooker tables, games, fees and daily club accounts', Icons.sports_esports_outlined, ['9+ Tables', 'Fixed Fee per Game', 'Player Results', 'Payments & Refunds', 'Refreshments POS', 'Cash Closing', 'PDF Reports']),
    _BusinessCategory('Pharmacy', 'Medical store and healthcare stock', Icons.medical_services_outlined, ['Batch & Expiry', 'Inventory', 'Purchases', 'POS Billing', 'Expiry Alerts', 'Reports']),
    _BusinessCategory('Vehicle Showroom', 'Car and motorcycle sales', Icons.directions_car_outlined, ['Vehicle Stock', 'Buy & Sell', 'Customer Ledger', 'Payments', 'Documents', 'Reports']),
    _BusinessCategory('Workshop', 'Vehicle and equipment repair', Icons.car_repair, ['Job Cards', 'Parts Usage', 'Labour Charges', 'Customer Approval', 'Payments', 'Warranty']),
    _BusinessCategory('Transport & Fleet', 'Passenger, cargo and delivery', Icons.local_shipping_outlined, ['Vehicles', 'Routes & Trips', 'Tickets', 'Passengers', 'Cargo / Loads', 'Fuel & Expenses']),
    _BusinessCategory('Rent-a-Car', 'Vehicle rental management', Icons.key_outlined, ['Fleet', 'Bookings', 'Rental Contracts', 'Deposits', 'Returns', 'Maintenance']),
    _BusinessCategory('School & Academy', 'Student records and fees', Icons.school_outlined, ['Students', 'Admissions', 'Fee Collection', 'Staff', 'Expenses', 'Reports']),
    _BusinessCategory('Clinic', 'Appointments and fee records', Icons.local_hospital_outlined, ['Appointments', 'Service Records', 'Fee Collection', 'Supplies', 'Staff Access', 'Reports']),
    _BusinessCategory('Salon & Spa', 'Appointments and services', Icons.spa_outlined, ['Appointments', 'Services', 'Staff', 'Products', 'Payments', 'Reports']),
    _BusinessCategory('Construction', 'Projects and contractors', Icons.construction_outlined, ['Projects', 'Materials', 'Purchase Orders', 'Labour', 'Project Expenses', 'Reports']),
    _BusinessCategory('Agriculture', 'Farm supplies and equipment', Icons.agriculture, ['Product Stock', 'Seasonal Purchases', 'Suppliers', 'Orders', 'Expenses', 'Reports']),
    _BusinessCategory('Public / Private Services', 'Office, agency and service work', Icons.business_center_outlined, ['Service Requests', 'Cases / Jobs', 'Customer Records', 'Payments', 'Expenses', 'Reports']),
    _BusinessCategory('Custom Business', 'Configure your own business type', Icons.tune, ['Custom Categories', 'Products / Services', 'Orders', 'Customers', 'Finance', 'Reports']),
  ];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final visible = _categories.where((category) =>
        category.name.toLowerCase().contains(query) ||
        category.description.toLowerCase().contains(query)).toList();
    final selected = _categories.firstWhere((category) => category.name == _selectedCategory);

    return Scaffold(
      backgroundColor: AppTheme.canvas,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.ink,
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0B3D91), Color(0xFF082B4C)],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          height: 48,
                          width: 48,
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
                          child: const _BrandMark(),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('SHOPKEEPER PRO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.1, fontSize: 17)),
                              SizedBox(height: 3),
                              Text('Aapki dukaan, ab zyada aasaan', style: TextStyle(color: Color(0xFFDCE8FF), fontSize: 12)),
                            ],
                          ),
                        ),
                        const Icon(Icons.notifications_none_rounded, color: Colors.white, size: 26),
                      ],
                    ),
                    const SizedBox(height: 26),
                    const Text('Business Center', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 27, letterSpacing: -0.5)),
                    const SizedBox(height: 6),
                    const Text('Apna business select karein ya tamam modules browse karein.', style: TextStyle(color: Color(0xFFE4ECFF), height: 1.4)),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(color: AppTheme.ink),
                      decoration: InputDecoration(
                        hintText: 'Business ya category search karein',
                        prefixIcon: const Icon(Icons.search_rounded),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    const Expanded(child: Text('Business categories', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppTheme.ink))),
                    Text('${visible.length} types', style: const TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 1.12,
                  crossAxisSpacing: 2,
                  mainAxisSpacing: 2,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final category = visible[index];
                    final isSelected = category.name == _selectedCategory;
                    return Card(
                      margin: const EdgeInsets.all(4),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => setState(() => _selectedCategory = category.name),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    height: 42,
                                    width: 42,
                                    decoration: BoxDecoration(
                                      color: isSelected ? AppTheme.teal.withValues(alpha: 0.17) : const Color(0xFFE7F0FF),
                                      borderRadius: BorderRadius.circular(13),
                                    ),
                                    child: Icon(category.icon, color: isSelected ? AppTheme.teal : AppTheme.ink),
                                  ),
                                  const Spacer(),
                                  if (isSelected) const Icon(Icons.check_circle_rounded, color: AppTheme.teal, size: 20),
                                ],
                              ),
                              const Spacer(),
                              Text(category.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.ink, fontSize: 14)),
                              const SizedBox(height: 4),
                              Text(category.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, height: 1.25, color: AppTheme.muted)),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  childCount: visible.length,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: AppTheme.line)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            height: 44,
                            width: 44,
                            decoration: BoxDecoration(color: AppTheme.gold.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(14)),
                            child: Icon(selected.icon, color: AppTheme.ink),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(selected.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.ink)),
                                const Text('Recommended modules', style: TextStyle(color: AppTheme.muted, fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: selected.modules.map((module) => Chip(
                          avatar: Icon(_moduleIcon(module), size: 17, color: AppTheme.ink),
                          label: Text(module),
                          backgroundColor: const Color(0xFFF3F6FB),
                          side: const BorderSide(color: AppTheme.line),
                          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.ink),
                        )).toList(),
                      ),
                      const SizedBox(height: 18),
                      const Text('Quick access', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.ink, fontSize: 15)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (selected.name == 'Snooker Club') _QuickAction(label: 'Open Snooker Club', icon: Icons.sports_esports_outlined, onTap: () => widget.onOpenModule(11)),
                          _QuickAction(label: 'POS Billing', icon: Icons.point_of_sale_outlined, onTap: () => widget.onOpenModule(1)),
                          _QuickAction(label: 'Inventory', icon: Icons.inventory_2_outlined, onTap: () => widget.onOpenModule(3)),
                          _QuickAction(label: 'Customers', icon: Icons.people_outline, onTap: () => widget.onOpenModule(2)),
                          _QuickAction(label: 'Sales', icon: Icons.trending_up_outlined, onTap: () => widget.onOpenModule(4)),
                          _QuickAction(label: 'Suppliers', icon: Icons.handshake_outlined, onTap: () => widget.onOpenModule(5)),
                          _QuickAction(label: 'Finance', icon: Icons.account_balance_wallet_outlined, onTap: () => widget.onOpenModule(6)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text('Note: Category cards organize the intended workflow. Category-specific features must be verified before being treated as production-ready.', style: TextStyle(fontSize: 11, height: 1.35, color: AppTheme.muted)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _moduleIcon(String module) {
    final value = module.toLowerCase();
    if (value.contains('stock') || value.contains('inventory') || value.contains('part')) return Icons.inventory_2_outlined;
    if (value.contains('sale') || value.contains('billing') || value.contains('payment') || value.contains('fee')) return Icons.receipt_long_outlined;
    if (value.contains('customer') || value.contains('passenger') || value.contains('student')) return Icons.people_outline;
    if (value.contains('repair') || value.contains('job') || value.contains('workshop')) return Icons.build;
    if (value.contains('purchase') || value.contains('supplier')) return Icons.local_shipping_outlined;
    if (value.contains('report') || value.contains('finance') || value.contains('expense')) return Icons.bar_chart_outlined;
    return Icons.apps_rounded;
  }
}

class _BusinessCategory {
  const _BusinessCategory(this.name, this.description, this.icon, this.modules);
  final String name;
  final String description;
  final IconData icon;
  final List<String> modules;
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ActionChip(
    avatar: Icon(icon, size: 18, color: AppTheme.ink),
    label: Text(label),
    onPressed: onTap,
    backgroundColor: Colors.white,
    side: const BorderSide(color: AppTheme.line),
    labelStyle: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.ink),
  );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(8),
    child: CustomPaint(painter: _BrandMarkPainter()),
  );
}

class _BrandMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final navy = Paint()..color = AppTheme.ink..style = PaintingStyle.stroke..strokeWidth = 2.5..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    final teal = Paint()..color = AppTheme.teal..style = PaintingStyle.fill;
    final gold = Paint()..color = AppTheme.gold..style = PaintingStyle.stroke..strokeWidth = 2.5..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    final cart = Path()..moveTo(size.width * .08, size.height * .18)..lineTo(size.width * .22, size.height * .18)..lineTo(size.width * .34, size.height * .69)..lineTo(size.width * .78, size.height * .69)..lineTo(size.width * .91, size.height * .35)..lineTo(size.width * .30, size.height * .35);
    canvas.drawPath(cart, navy);
    canvas.drawCircle(Offset(size.width * .42, size.height * .84), size.width * .055, teal);
    canvas.drawCircle(Offset(size.width * .72, size.height * .84), size.width * .055, teal);
    final growth = Path()..moveTo(size.width * .40, size.height * .51)..lineTo(size.width * .54, size.height * .39)..lineTo(size.width * .66, size.height * .46)..lineTo(size.width * .82, size.height * .23);
    canvas.drawPath(growth, gold);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
