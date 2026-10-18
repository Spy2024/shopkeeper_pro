import 'dart:io';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Owns one SQLite database per authenticated Firebase UID.
class DBService {
  DBService._internal();
  static final DBService instance = DBService._internal();

  Database? _db;
  String? _activeUserId;

  String? get activeUserId => _activeUserId;

  Future<Database> get database async {
    final userId = _activeUserId;
    if (userId == null || userId.isEmpty) {
      throw StateError('No authenticated user database is active.');
    }
    _db ??= await _initDb(userId);
    return _db!;
  }

  /// Selects an isolated local database for the authenticated user.
  Future<void> configureForUser(String userId) async {
    final normalized = userId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'Must not be empty.');
    }
    if (_activeUserId == normalized && _db != null) return;

    await _db?.close();
    _db = null;
    _activeUserId = normalized;

    final root = await getDatabasesPath();
    final legacyPath = join(root, 'shopkeeper_pro.db');
    final targetPath = _userDatabasePath(root, normalized);
    final migrationMarker = join(root, 'shopkeeper_pro_legacy_migrated.flag');

    // Preserve old local data for the first account that signs in after this
    // upgrade. Never copy the legacy database into subsequent accounts.
    if (!await File(migrationMarker).exists() &&
        await File(legacyPath).exists() &&
        !await File(targetPath).exists()) {
      await File(legacyPath).copy(targetPath);
      await File(migrationMarker).writeAsString(normalized, flush: true);
    }
  }

  Future<void> clearActiveUser() async {
    await _db?.close();
    _db = null;
    _activeUserId = null;
  }

  String _userDatabasePath(String root, String userId) {
    final safeId = userId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return join(root, 'shopkeeper_pro_$safeId.db');
  }

  Future<Database> _initDb(String userId) async {
    final root = await getDatabasesPath();
    final path = _userDatabasePath(root, userId);
    return openDatabase(
      path,
      version: 5,
      onCreate: (db, version) async => _createSchema(db),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''CREATE TABLE IF NOT EXISTS sync_queue (
            id TEXT PRIMARY KEY, operation TEXT NOT NULL, tableName TEXT NOT NULL,
            documentId TEXT NOT NULL, data TEXT NOT NULL, timestamp INTEGER NOT NULL,
            synced INTEGER NOT NULL DEFAULT 0)''');
        }
        if (oldVersion < 5) {
          await _createBusinessTables(db);
          await db.execute('ALTER TABLE bills ADD COLUMN branchId TEXT');
        }
      },
    );
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('CREATE TABLE shop (id TEXT PRIMARY KEY, name TEXT NOT NULL, address TEXT NOT NULL, phone TEXT NOT NULL, taxNumber TEXT, logoPath TEXT)');
    await db.execute('CREATE TABLE products (id TEXT PRIMARY KEY, name TEXT NOT NULL, category TEXT NOT NULL, stockQuantity INTEGER NOT NULL DEFAULT 0, costPrice REAL NOT NULL DEFAULT 0, sellingPrice REAL NOT NULL DEFAULT 0, lowStockThreshold INTEGER NOT NULL DEFAULT 5)');
    await db.execute('CREATE TABLE bills (id TEXT PRIMARY KEY, date TEXT NOT NULL, customerName TEXT, discount REAL NOT NULL DEFAULT 0, taxPercent REAL NOT NULL DEFAULT 0, branchId TEXT)');
    await db.execute('CREATE TABLE bill_items (id INTEGER PRIMARY KEY AUTOINCREMENT, billId TEXT NOT NULL, productName TEXT NOT NULL, quantity INTEGER NOT NULL, unitPrice REAL NOT NULL, FOREIGN KEY (billId) REFERENCES bills(id) ON DELETE CASCADE)');
    await db.execute('CREATE TABLE suppliers (id TEXT PRIMARY KEY, name TEXT NOT NULL, phone TEXT NOT NULL, totalStockReceivedValue REAL NOT NULL DEFAULT 0, totalPaymentsMade REAL NOT NULL DEFAULT 0)');
    await db.execute('CREATE TABLE supplier_orders (id TEXT PRIMARY KEY, supplierId TEXT NOT NULL, supplierName TEXT NOT NULL, date TEXT NOT NULL, status TEXT NOT NULL DEFAULT "draft")');
    await db.execute('CREATE TABLE supplier_order_items (id INTEGER PRIMARY KEY AUTOINCREMENT, orderId TEXT NOT NULL, productName TEXT NOT NULL, requiredQuantity INTEGER NOT NULL, estimatedPrice REAL NOT NULL, FOREIGN KEY (orderId) REFERENCES supplier_orders(id) ON DELETE CASCADE)');
    await db.execute('CREATE TABLE daily_sales (id TEXT PRIMARY KEY, date TEXT NOT NULL, productName TEXT NOT NULL, costPrice REAL NOT NULL, salePrice REAL NOT NULL)');
    await db.execute('CREATE TABLE expenses (id TEXT PRIMARY KEY, date TEXT NOT NULL, label TEXT NOT NULL, amount REAL NOT NULL)');
    await db.execute('CREATE TABLE sync_queue (id TEXT PRIMARY KEY, operation TEXT NOT NULL, tableName TEXT NOT NULL, documentId TEXT NOT NULL, data TEXT NOT NULL, timestamp INTEGER NOT NULL, synced INTEGER NOT NULL DEFAULT 0)');
    await _createBusinessTables(db);
  }

  Future<void> _createBusinessTables(Database db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS customers (id TEXT PRIMARY KEY, name TEXT NOT NULL, phone TEXT, address TEXT, email TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS customer_ledger (id TEXT PRIMARY KEY, customerId TEXT NOT NULL, date TEXT NOT NULL, type TEXT NOT NULL, amount REAL NOT NULL, referenceId TEXT, note TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS payments (id TEXT PRIMARY KEY, billId TEXT NOT NULL, method TEXT NOT NULL, amount REAL NOT NULL, reference TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS returns (id TEXT PRIMARY KEY, billId TEXT NOT NULL, date TEXT NOT NULL, customerName TEXT, refundAmount REAL NOT NULL, reason TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS return_items (id TEXT PRIMARY KEY, returnId TEXT NOT NULL, productId TEXT, productName TEXT NOT NULL, quantity INTEGER NOT NULL, unitPrice REAL NOT NULL)');
    await db.execute('CREATE TABLE IF NOT EXISTS branches (id TEXT PRIMARY KEY, name TEXT NOT NULL, address TEXT, phone TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS branch_stock (id TEXT PRIMARY KEY, branchId TEXT NOT NULL, productId TEXT NOT NULL, quantity INTEGER NOT NULL DEFAULT 0)');
    await db.execute('CREATE TABLE IF NOT EXISTS branch_cash_entries (id TEXT PRIMARY KEY, branchId TEXT NOT NULL, date TEXT NOT NULL, type TEXT NOT NULL, amount REAL NOT NULL, note TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS product_variants (id TEXT PRIMARY KEY, productId TEXT NOT NULL, size TEXT, color TEXT, sku TEXT, quantity INTEGER NOT NULL DEFAULT 0)');
    await db.execute('CREATE TABLE IF NOT EXISTS mobile_devices (id TEXT PRIMARY KEY, productId TEXT, imei TEXT UNIQUE NOT NULL, serialNumber TEXT, status TEXT NOT NULL DEFAULT "in_stock", purchasePrice REAL NOT NULL DEFAULT 0, salePrice REAL NOT NULL DEFAULT 0, billId TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS restaurant_tables (id TEXT PRIMARY KEY, name TEXT NOT NULL, capacity INTEGER NOT NULL DEFAULT 2, status TEXT NOT NULL DEFAULT "available")');
    await db.execute('CREATE TABLE IF NOT EXISTS restaurant_orders (id TEXT PRIMARY KEY, tableId TEXT, status TEXT NOT NULL DEFAULT "open", total REAL NOT NULL DEFAULT 0, createdAt TEXT NOT NULL)');
    await db.execute('CREATE TABLE IF NOT EXISTS vehicle_records (id TEXT PRIMARY KEY, type TEXT NOT NULL, make TEXT, model TEXT, registrationNumber TEXT, vin TEXT, status TEXT NOT NULL DEFAULT "in_stock", purchasePrice REAL NOT NULL DEFAULT 0, salePrice REAL NOT NULL DEFAULT 0)');
    await db.execute('CREATE TABLE IF NOT EXISTS transport_routes (id TEXT PRIMARY KEY, name TEXT NOT NULL, origin TEXT, destination TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS transport_tickets (id TEXT PRIMARY KEY, routeId TEXT NOT NULL, passengerName TEXT NOT NULL, seatNumber TEXT, travelDate TEXT NOT NULL, fare REAL NOT NULL, status TEXT NOT NULL DEFAULT "booked")');
    await db.execute('CREATE TABLE IF NOT EXISTS cargo_jobs (id TEXT PRIMARY KEY, routeId TEXT, customerName TEXT NOT NULL, loadDescription TEXT, weight REAL NOT NULL DEFAULT 0, freightAmount REAL NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT "created")');
    await db.execute('CREATE TABLE IF NOT EXISTS service_jobs (id TEXT PRIMARY KEY, customerName TEXT NOT NULL, deviceOrVehicle TEXT, issue TEXT NOT NULL, status TEXT NOT NULL DEFAULT "received", estimatedCost REAL NOT NULL DEFAULT 0, finalCost REAL NOT NULL DEFAULT 0, createdAt TEXT NOT NULL)');
  }
}
