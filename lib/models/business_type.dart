/// Business types supported by the Shopkeeper Pro setup selector.
///
/// This catalog describes the intended module defaults for each business type.
/// A catalog entry is not proof that every listed operational workflow is
/// implemented; module readiness is tracked in docs/MASTER_PRODUCT_SCOPE.md.
class BusinessTypeOption {
  final String id;
  final String label;
  final List<String> defaultModules;

  const BusinessTypeOption({
    required this.id,
    required this.label,
    required this.defaultModules,
  });
}

class BusinessTypes {
  BusinessTypes._();

  static const List<BusinessTypeOption> all = [
    BusinessTypeOption(id: 'general_retail', label: 'General Store / Retail', defaultModules: ['pos', 'inventory', 'purchases', 'customers', 'suppliers', 'expenses', 'reports']),
    BusinessTypeOption(id: 'wholesale_distribution', label: 'Wholesale / Distribution', defaultModules: ['pos', 'inventory', 'purchases', 'customers', 'suppliers', 'credit_ledger', 'warehouse', 'reports']),
    BusinessTypeOption(id: 'clothing', label: 'Clothing / Garments', defaultModules: ['pos', 'inventory', 'variants', 'purchases', 'customers', 'reports']),
    BusinessTypeOption(id: 'shoes', label: 'Shoes / Footwear', defaultModules: ['pos', 'inventory', 'variants', 'purchases', 'customers', 'reports']),
    BusinessTypeOption(id: 'mobile_electronics', label: 'Mobile / Electronics', defaultModules: ['pos', 'inventory', 'serial_numbers', 'warranty', 'repairs', 'purchases', 'reports']),
    BusinessTypeOption(id: 'pharmacy', label: 'Pharmacy / Medical Store', defaultModules: ['pos', 'inventory', 'batch_expiry', 'purchases', 'suppliers', 'reports']),
    BusinessTypeOption(id: 'hardware', label: 'Hardware / Building Materials', defaultModules: ['pos', 'inventory', 'units', 'purchases', 'delivery', 'reports']),
    BusinessTypeOption(id: 'cosmetics', label: 'Cosmetics / Beauty Products', defaultModules: ['pos', 'inventory', 'batch_expiry', 'purchases', 'customers', 'reports']),
    BusinessTypeOption(id: 'supermarket', label: 'Supermarket', defaultModules: ['pos', 'inventory', 'barcode', 'purchases', 'cashbook', 'staff', 'reports']),
    BusinessTypeOption(id: 'restaurant_cafe', label: 'Restaurant / Cafe', defaultModules: ['pos', 'menu', 'tables', 'kitchen_orders', 'inventory', 'expenses', 'reports']),
    BusinessTypeOption(id: 'car_showroom', label: 'Car Showroom / Dealership', defaultModules: ['vehicles', 'vehicle_sales', 'vehicle_purchases', 'customers', 'finance', 'documents', 'reports']),
    BusinessTypeOption(id: 'motorcycle_showroom', label: 'Motorcycle Showroom', defaultModules: ['vehicles', 'vehicle_sales', 'vehicle_purchases', 'customers', 'finance', 'documents', 'reports']),
    BusinessTypeOption(id: 'vehicle_workshop', label: 'Vehicle Workshop / Service Center', defaultModules: ['job_cards', 'service_parts', 'customers', 'technicians', 'estimates', 'invoices', 'reports']),
    BusinessTypeOption(id: 'trucking_fleet', label: 'Trucking / Fleet Management', defaultModules: ['vehicles', 'drivers', 'trips', 'fuel', 'maintenance', 'route_costs', 'freight_invoices', 'reports']),
    BusinessTypeOption(id: 'passenger_transport', label: 'Passenger Transport', defaultModules: ['vehicles', 'drivers', 'routes', 'schedules', 'tickets', 'fuel', 'maintenance', 'reports']),
    BusinessTypeOption(id: 'goods_transport', label: 'Goods / Cargo Transport', defaultModules: ['vehicles', 'drivers', 'shipments', 'consignments', 'fuel', 'maintenance', 'freight_invoices', 'reports']),
    BusinessTypeOption(id: 'rent_a_car', label: 'Rent a Car', defaultModules: ['vehicles', 'bookings', 'rental_agreements', 'deposits', 'drivers', 'maintenance', 'reports']),
    BusinessTypeOption(id: 'public_services', label: 'Public Service Office', defaultModules: ['service_requests', 'appointments', 'documents', 'fees', 'queues', 'reports']),
    BusinessTypeOption(id: 'private_services', label: 'Private Services / Agency', defaultModules: ['service_requests', 'appointments', 'customers', 'invoices', 'expenses', 'reports']),
    BusinessTypeOption(id: 'repair_service', label: 'Repair / Maintenance Business', defaultModules: ['job_cards', 'estimates', 'service_parts', 'technicians', 'invoices', 'reports']),
    BusinessTypeOption(id: 'salon_spa', label: 'Salon / Spa', defaultModules: ['appointments', 'services', 'staff', 'customers', 'packages', 'reports']),
    BusinessTypeOption(id: 'school_academy', label: 'School / Academy', defaultModules: ['students', 'admissions', 'fees', 'attendance', 'staff', 'reports']),
    BusinessTypeOption(id: 'clinic', label: 'Clinic / Healthcare Practice', defaultModules: ['patients', 'appointments', 'services', 'invoices', 'expenses', 'reports']),
    BusinessTypeOption(id: 'agriculture', label: 'Agriculture / Farm Supplies', defaultModules: ['inventory', 'purchases', 'harvests', 'inputs', 'customers', 'reports']),
    BusinessTypeOption(id: 'construction', label: 'Construction / Contractor', defaultModules: ['projects', 'estimates', 'materials', 'workers', 'payments', 'expenses', 'reports']),
    BusinessTypeOption(id: 'other', label: 'Other Business', defaultModules: ['pos', 'inventory', 'customers', 'suppliers', 'expenses', 'reports']),
  ];

  static BusinessTypeOption byId(String? id) => all.firstWhere(
        (item) => item.id == id,
        orElse: () => all.first,
      );
}
