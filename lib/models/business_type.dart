/// Business types supported by the Shopkeeper Pro setup selector.
///
/// This catalog describes intended module defaults. A catalog entry is not
/// proof that every listed operational workflow is implemented; readiness is
/// tracked in docs/MASTER_PRODUCT_SCOPE.md.
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
    BusinessTypeOption(
      id: 'mobile_electronics',
      label: 'Mobile Shop / Electronics',
      defaultModules: [
        'pos',
        'inventory',
        'purchases',
        'suppliers',
        'customers',
        'new_devices',
        'used_device_intake',
        'imei_tracking',
        'mobile_accessories',
        'mobile_parts',
        'repair_job_cards',
        'software_services',
        'device_condition_checklist',
        'warranty_tracking',
        'credit_ledger',
        'expenses',
        'reports',
      ],
    ),
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

    // Spare-parts businesses share the core POS/inventory foundation but need
    // fitment, cross-reference and part-number capabilities in their workflow.
    BusinessTypeOption(id: 'spare_parts', label: 'Spare Parts (All Types)', defaultModules: ['pos', 'inventory', 'part_catalog', 'fitment_compatibility', 'cross_reference', 'barcode', 'purchases', 'suppliers', 'stock_ledger', 'warranty', 'reports']),
    BusinessTypeOption(id: 'motorcycle_spare_parts', label: 'Bike / Motorcycle Spare Parts', defaultModules: ['pos', 'inventory', 'part_catalog', 'fitment_compatibility', 'cross_reference', 'barcode', 'purchases', 'suppliers', 'stock_ledger', 'warranty', 'reports']),
    BusinessTypeOption(id: 'car_spare_parts', label: 'Car / Auto Spare Parts', defaultModules: ['pos', 'inventory', 'part_catalog', 'fitment_compatibility', 'cross_reference', 'barcode', 'purchases', 'suppliers', 'stock_ledger', 'warranty', 'reports']),
    BusinessTypeOption(id: 'heavy_vehicle_spare_parts', label: 'Truck / Bus / Heavy Vehicle Parts', defaultModules: ['pos', 'inventory', 'part_catalog', 'fitment_compatibility', 'cross_reference', 'barcode', 'purchases', 'suppliers', 'stock_ledger', 'warranty', 'reports']),
    BusinessTypeOption(id: 'mobile_spare_parts', label: 'Mobile Phone Spare Parts', defaultModules: ['pos', 'inventory', 'part_catalog', 'device_model_compatibility', 'serial_numbers', 'barcode', 'purchases', 'suppliers', 'stock_ledger', 'warranty', 'reports']),
    BusinessTypeOption(id: 'computer_spare_parts', label: 'Computer / Laptop Spare Parts', defaultModules: ['pos', 'inventory', 'part_catalog', 'device_model_compatibility', 'serial_numbers', 'barcode', 'purchases', 'suppliers', 'stock_ledger', 'warranty', 'reports']),
    BusinessTypeOption(id: 'home_appliance_spare_parts', label: 'Home Appliance Spare Parts', defaultModules: ['pos', 'inventory', 'part_catalog', 'brand_model_compatibility', 'barcode', 'purchases', 'suppliers', 'stock_ledger', 'warranty', 'reports']),
    BusinessTypeOption(id: 'electrical_electronics_parts', label: 'Electrical / Electronics Spare Parts', defaultModules: ['pos', 'inventory', 'part_catalog', 'specifications', 'barcode', 'purchases', 'suppliers', 'stock_ledger', 'warranty', 'reports']),
    BusinessTypeOption(id: 'industrial_machinery_parts', label: 'Industrial Machinery Spare Parts', defaultModules: ['pos', 'inventory', 'part_catalog', 'machine_compatibility', 'cross_reference', 'barcode', 'purchases', 'suppliers', 'stock_ledger', 'reports']),
    BusinessTypeOption(id: 'agricultural_machinery_parts', label: 'Tractor / Agricultural Machinery Parts', defaultModules: ['pos', 'inventory', 'part_catalog', 'machine_compatibility', 'cross_reference', 'barcode', 'purchases', 'suppliers', 'stock_ledger', 'reports']),
    BusinessTypeOption(id: 'generator_engine_parts', label: 'Generator / Engine Spare Parts', defaultModules: ['pos', 'inventory', 'part_catalog', 'engine_compatibility', 'cross_reference', 'barcode', 'purchases', 'suppliers', 'stock_ledger', 'reports']),
    BusinessTypeOption(id: 'plumbing_sanitary_parts', label: 'Plumbing / Sanitary Fittings & Parts', defaultModules: ['pos', 'inventory', 'part_catalog', 'sizes_dimensions', 'barcode', 'purchases', 'suppliers', 'stock_ledger', 'reports']),
    BusinessTypeOption(id: 'other_spare_parts', label: 'Other Spare Parts', defaultModules: ['pos', 'inventory', 'part_catalog', 'fitment_compatibility', 'cross_reference', 'barcode', 'purchases', 'suppliers', 'stock_ledger', 'reports']),

    BusinessTypeOption(id: 'other', label: 'Other Business', defaultModules: ['pos', 'inventory', 'customers', 'suppliers', 'expenses', 'reports']),
  ];

  static BusinessTypeOption byId(String? id) => all.firstWhere(
        (item) => item.id == id,
        orElse: () => all.first,
      );
}
