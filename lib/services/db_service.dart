import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DBService {
  DBService._internal();
  static final DBService instance = DBService._internal();
  Database? _db;
  String? _activeUserId;

  String? get activeUserId => _activeUserId;

  /// Selects a separate local database for each authenticated account.
  /// Existing installs are migrated to the first account that signs in; the
  /// legacy file is retained only if the scoped destination already exists.
  Future<void> configureForUser(String userId) async {
    final cleanId = userId.trim();
    if (cleanId.isEmpty) throw ArgumentError('A non-empty user ID is required.');
    if (_activeUserId == cleanId && _db != null) return;
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
    final dbPath = await getDatabasesPath();
    final legacyPath = join(dbPath, 'shopkeeper_pro.db');
    final safeId = cleanId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final userPath = join(dbPath, 'shopkeeper_pro_$safeId.db');
    final legacyFile = File(legacyPath);
    final userFile = File(userPath);
    if (!await userFile.exists() && await legacyFile.exists()) {
      await legacyFile.rename(userPath);
      for (final suffix in ['-wal', '-shm']) {
        final sidecar = File('$legacyPath$suffix');
        if (await sidecar.exists()) {
          await sidecar.rename('$userPath$suffix');
        }
      }
    }
    _activeUserId = cleanId;
    _db = await _openAt(userPath);
  }

  Future<void> clearActiveUser() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
    _activeUserId = null;
  }


  Future<void> deleteActiveUserDatabase(String expectedUserId) async {
    if (_activeUserId != expectedUserId) {
      throw StateError('Refusing to delete a database owned by another account.');
    }
    final dbPath = await getDatabasesPath();
    final safeId = expectedUserId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final userPath = join(dbPath, 'shopkeeper_pro_$safeId.db');
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
    _activeUserId = null;
    for (final suffix in ['', '-wal', '-shm']) {
      final file = File('$userPath$suffix');
      if (await file.exists()) await file.delete();
    }
  }

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    final path = _activeUserId == null
        ? join(dbPath, 'shopkeeper_pro.db')
        : join(dbPath, 'shopkeeper_pro_${_activeUserId!.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.db');
    _db = await _openAt(path);
    return _db!;
  }

  Future<Database> _openAt(String path) async {
    return openDatabase(
      path,
      version: 6,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) => _createSchema(db),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createSyncQueue(db);
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE bill_items ADD COLUMN cloudId TEXT');
          await db.execute('ALTER TABLE supplier_order_items ADD COLUMN cloudId TEXT');
          await db.execute('UPDATE bill_items SET cloudId = CAST(id AS TEXT) WHERE cloudId IS NULL');
          await db.execute('UPDATE supplier_order_items SET cloudId = CAST(id AS TEXT) WHERE cloudId IS NULL');
        }
        if (oldVersion < 4) {
          await db.execute('ALTER TABLE bill_items ADD COLUMN productId TEXT');
          await db.execute('ALTER TABLE daily_sales ADD COLUMN billId TEXT');
          await db.execute('ALTER TABLE daily_sales ADD COLUMN productId TEXT');
          await db.execute("ALTER TABLE daily_sales ADD COLUMN source TEXT NOT NULL DEFAULT 'manual'");
          await db.execute('CREATE INDEX IF NOT EXISTS idx_bill_items_billId ON bill_items(billId)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_date ON daily_sales(date)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_billId ON daily_sales(billId)');
        }
        if (oldVersion < 5) {
          await db.execute('CREATE TABLE IF NOT EXISTS supplier_transactions (id TEXT PRIMARY KEY, supplierId TEXT NOT NULL, type TEXT NOT NULL, amount REAL NOT NULL, date TEXT NOT NULL, referenceId TEXT, FOREIGN KEY (supplierId) REFERENCES suppliers(id) ON DELETE CASCADE)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_supplier_transactions_supplier ON supplier_transactions(supplierId, date)');
        }
        if (oldVersion < 6) {
          await db.execute('ALTER TABLE daily_sales ADD COLUMN quantity INTEGER NOT NULL DEFAULT 1');
          await db.execute("""
            UPDATE daily_sales
            SET quantity = COALESCE((
              SELECT SUM(bi.quantity)
              FROM bill_items bi
              WHERE bi.billId = daily_sales.billId
                AND (bi.productId = daily_sales.productId
                  OR (bi.productId IS NULL AND bi.productName = daily_sales.productName))
            ), 1)
            WHERE daily_sales.source = 'pos'
          """);
        }
      },
    );
  }

  Future<void> _createSyncQueue(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_queue (
        id TEXT PRIMARY KEY,
        operation TEXT NOT NULL,
        tableName TEXT NOT NULL,
        documentId TEXT NOT NULL,
        data TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('CREATE TABLE shop (id TEXT PRIMARY KEY, name TEXT NOT NULL, address TEXT, phone TEXT, taxNumber TEXT, logoPath TEXT)');
    await db.execute('CREATE TABLE products (id TEXT PRIMARY KEY, name TEXT NOT NULL, category TEXT, stockQuantity INTEGER NOT NULL DEFAULT 0, costPrice REAL NOT NULL DEFAULT 0, sellingPrice REAL NOT NULL DEFAULT 0, lowStockThreshold INTEGER NOT NULL DEFAULT 5)');
    await db.execute('CREATE TABLE bills (id TEXT PRIMARY KEY, date TEXT NOT NULL, customerName TEXT, discount REAL NOT NULL DEFAULT 0, taxPercent REAL NOT NULL DEFAULT 0)');
    await db.execute('CREATE TABLE bill_items (id INTEGER PRIMARY KEY AUTOINCREMENT, billId TEXT NOT NULL, productId TEXT, productName TEXT NOT NULL, quantity INTEGER NOT NULL, unitPrice REAL NOT NULL, cloudId TEXT, FOREIGN KEY (billId) REFERENCES bills (id) ON DELETE CASCADE)');
    await db.execute('CREATE TABLE suppliers (id TEXT PRIMARY KEY, name TEXT NOT NULL, phone TEXT, totalStockReceivedValue REAL NOT NULL DEFAULT 0, totalPaymentsMade REAL NOT NULL DEFAULT 0)');
    await db.execute("CREATE TABLE supplier_orders (id TEXT PRIMARY KEY, supplierId TEXT NOT NULL, supplierName TEXT NOT NULL, date TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'draft')");
    await db.execute('CREATE TABLE supplier_order_items (id INTEGER PRIMARY KEY AUTOINCREMENT, orderId TEXT NOT NULL, productName TEXT NOT NULL, requiredQuantity INTEGER NOT NULL, estimatedPrice REAL NOT NULL, cloudId TEXT, FOREIGN KEY (orderId) REFERENCES supplier_orders (id) ON DELETE CASCADE)');
    await db.execute("CREATE TABLE daily_sales (id TEXT PRIMARY KEY, date TEXT NOT NULL, billId TEXT, productId TEXT, productName TEXT NOT NULL, costPrice REAL NOT NULL, salePrice REAL NOT NULL, quantity INTEGER NOT NULL DEFAULT 1, source TEXT NOT NULL DEFAULT 'manual')");
    await db.execute('CREATE TABLE expenses (id TEXT PRIMARY KEY, date TEXT NOT NULL, label TEXT NOT NULL, amount REAL NOT NULL)');
    await _createSyncQueue(db);
    await db.execute('CREATE TABLE supplier_transactions (id TEXT PRIMARY KEY, supplierId TEXT NOT NULL, type TEXT NOT NULL, amount REAL NOT NULL, date TEXT NOT NULL, referenceId TEXT, FOREIGN KEY (supplierId) REFERENCES suppliers(id) ON DELETE CASCADE)');
    await db.execute('CREATE INDEX idx_supplier_transactions_supplier ON supplier_transactions(supplierId, date)');
    await db.execute('CREATE INDEX idx_products_name ON products(name)');
    await db.execute('CREATE INDEX idx_bill_items_billId ON bill_items(billId)');
    await db.execute('CREATE INDEX idx_sales_date ON daily_sales(date)');
    await db.execute('CREATE INDEX idx_sales_billId ON daily_sales(billId)');
  }
}
