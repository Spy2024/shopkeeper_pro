import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class LegacyDatabaseMigrationRequired implements Exception {
  const LegacyDatabaseMigrationRequired();

  @override
  String toString() =>
      'An older local database was found. Confirm that this data belongs to this account before importing it.';
}

class LegacyDatabaseOwnershipConflict implements Exception {
  const LegacyDatabaseOwnershipConflict();

  @override
  String toString() =>
      'The old local database has already been assigned to a different account. It was not imported.';
}

class DBService {
  DBService._internal();
  static final DBService instance = DBService._internal();
  Database? _db;
  String? _activeUserId;

  String? get activeUserId => _activeUserId;

  /// Selects a separate local database for each authenticated account.
  /// Never assigns an unscoped legacy database to an account without explicit
  /// confirmation from the user.
  Future<void> configureForUser(String userId) async {
    final cleanId = userId.trim();
    if (cleanId.isEmpty) throw ArgumentError('A non-empty user ID is required.');
    if (_activeUserId == cleanId && _db != null) return;
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
    // Clear ownership before opening another account's file. If opening the
    // new database fails, the previous account must not remain active.
    _activeUserId = null;
    final dbPath = await getDatabasesPath();
    final legacyPath = join(dbPath, 'shopkeeper_pro.db');
    final safeId = cleanId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final userPath = join(dbPath, 'shopkeeper_pro_$safeId.db');
    final legacyFile = File(legacyPath);
    final userFile = File(userPath);
    if (!await userFile.exists() && await legacyFile.exists()) {
      final ownerMarker = File(join(dbPath, 'shopkeeper_pro.legacy-owner'));
      if (await ownerMarker.exists()) {
        final ownerId = (await ownerMarker.readAsString()).trim();
        if (ownerId.isEmpty || ownerId != cleanId) {
          throw const LegacyDatabaseOwnershipConflict();
        }
      }
      throw const LegacyDatabaseMigrationRequired();
    }
    final openedDb = await _openAt(userPath);
    _db = openedDb;
    _activeUserId = cleanId;
  }

  /// Imports the old unscoped database only after the signed-in user explicitly
  /// confirms ownership. The original legacy file is copied, not moved, so it
  /// remains available for recovery if the imported database needs inspection.
  Future<void> migrateLegacyDatabaseForUser(
    String userId, {
    required bool confirmOwnership,
  }) async {
    final cleanId = userId.trim();
    if (cleanId.isEmpty) {
      throw ArgumentError('A non-empty user ID is required.');
    }
    if (!confirmOwnership) {
      throw StateError('Legacy database import requires explicit ownership confirmation.');
    }
    if (_activeUserId != null && _activeUserId != cleanId) {
      await clearActiveUser();
    } else if (_db != null) {
      await clearActiveUser();
    }

    final dbPath = await getDatabasesPath();
    final legacyPath = join(dbPath, 'shopkeeper_pro.db');
    final safeId = cleanId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final userPath = join(dbPath, 'shopkeeper_pro_$safeId.db');
    final legacyFile = File(legacyPath);
    final userFile = File(userPath);
    final ownerMarker = File(join(dbPath, 'shopkeeper_pro.legacy-owner'));

    if (!await userFile.exists()) {
      if (!await legacyFile.exists()) {
        throw StateError('The old local database could not be found. No data was imported.');
      }
      if (await ownerMarker.exists()) {
        final ownerId = (await ownerMarker.readAsString()).trim();
        if (ownerId.isEmpty || ownerId != cleanId) {
          throw const LegacyDatabaseOwnershipConflict();
        }
      }
      // The database connection is closed before copying. Copy sidecars too in
      // case a platform still has SQLite WAL data waiting to be checkpointed.
      await legacyFile.copy(userPath);
      Database? importedDb;
      try {
        for (final suffix in ['-wal', '-shm']) {
          final source = File('$legacyPath$suffix');
          if (await source.exists()) {
            await source.copy('$userPath$suffix');
          }
        }
        final imported = await _openAt(userPath);
        importedDb = imported;
        if (!await ownerMarker.exists()) {
          final temporaryMarker = File('${ownerMarker.path}.tmp');
          await temporaryMarker.writeAsString(cleanId, flush: true);
          await temporaryMarker.rename(ownerMarker.path);
        }
        _db = imported;
        _activeUserId = cleanId;
      } catch (_) {
        if (importedDb != null) {
          try {
            await importedDb.close();
          } catch (_) {
            // The source legacy database remains untouched for recovery.
          }
        }
        _db = null;
        _activeUserId = null;
        for (final suffix in ['', '-wal', '-shm']) {
          final copied = File('$userPath$suffix');
          if (await copied.exists()) {
            try {
              await copied.delete();
            } catch (_) {
              // Preserve the original legacy database even if cleanup fails.
            }
          }
        }
        rethrow;
      }
      return;
    }

    final openedDb = await _openAt(userPath);
    _db = openedDb;
    _activeUserId = cleanId;
  }

  Future<void> clearActiveUser() async {
    // Drop the active reference before awaiting close. Even if SQLite reports
    // a close error, callers must not keep using the previous account context.
    final previousDb = _db;
    _db = null;
    _activeUserId = null;
    if (previousDb != null) {
      await previousDb.close();
    }
  }


  Future<void> deleteActiveUserDatabase(String expectedUserId) async {
    if (_activeUserId != expectedUserId) {
      throw StateError('Refusing to delete a database owned by another account.');
    }
    final dbPath = await getDatabasesPath();
    final safeId = expectedUserId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final userPath = join(dbPath, 'shopkeeper_pro_$safeId.db');
    final previousDb = _db;
    _db = null;
    _activeUserId = null;
    if (previousDb != null) {
      await previousDb.close();
    }
    for (final suffix in ['', '-wal', '-shm']) {
      final file = File('$userPath$suffix');
      if (await file.exists()) await file.delete();
    }
  }

  Future<Database> get database async {
    // Fail closed: never open the legacy/unscoped database while no account
    // owns the active connection. Authenticated/demo sessions must call
    // configureForUser() before any provider accesses local data.
    final activeUserId = _activeUserId;
    if (activeUserId == null || activeUserId.trim().isEmpty) {
      throw StateError('Sign in before accessing the local database.');
    }
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    final safeId = activeUserId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final path = join(dbPath, 'shopkeeper_pro_$safeId.db');
    _db = await _openAt(path);
    return _db!;
  }

  Future<Database> _openAt(String path) async {
    return openDatabase(
      path,
      version: 12,
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
        if (oldVersion < 7) {
          await db.execute('CREATE TABLE IF NOT EXISTS bill_returns (id TEXT PRIMARY KEY, billId TEXT NOT NULL, productId TEXT NOT NULL, productName TEXT NOT NULL, quantity INTEGER NOT NULL CHECK(quantity > 0), refundAmount REAL NOT NULL, date TEXT NOT NULL, reason TEXT NOT NULL, FOREIGN KEY (billId) REFERENCES bills(id) ON DELETE CASCADE)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_bill_returns_bill_product ON bill_returns(billId, productId)');
        }
        if (oldVersion < 8) {
          await db.execute('CREATE TABLE IF NOT EXISTS customers (id TEXT PRIMARY KEY, name TEXT NOT NULL, phone TEXT, email TEXT, notes TEXT, createdAt TEXT NOT NULL)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_customers_name ON customers(name)');
        }
        if (oldVersion < 9) {
          await db.execute('ALTER TABLE bill_returns ADD COLUMN unitPrice REAL NOT NULL DEFAULT 0');
        }
        if (oldVersion < 10) {
          await db.execute('CREATE TABLE IF NOT EXISTS sync_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
        }
        if (oldVersion < 11) {
          await db.execute('ALTER TABLE products ADD COLUMN barcode TEXT');
          await db.execute('ALTER TABLE products ADD COLUMN expiryDate TEXT');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_products_expiryDate ON products(expiryDate)');
        }
        if (oldVersion < 12) {
          await db.execute("ALTER TABLE shop ADD COLUMN businessType TEXT NOT NULL DEFAULT 'general_retail'");
          await _createBranchesTable(db);
        }
      },
    );
  }

  Future<void> _createBranchesTable(Database db) async {
    await db.execute("""
      CREATE TABLE IF NOT EXISTS branches (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        code TEXT NOT NULL UNIQUE,
        address TEXT,
        phone TEXT,
        managerName TEXT,
        isMain INTEGER NOT NULL DEFAULT 0,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL
      )
    """);
    await db.execute('CREATE INDEX IF NOT EXISTS idx_branches_active ON branches(isActive)');
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
    await db.execute("CREATE TABLE shop (id TEXT PRIMARY KEY, name TEXT NOT NULL, address TEXT, phone TEXT, taxNumber TEXT, logoPath TEXT, businessType TEXT NOT NULL DEFAULT 'general_retail')");
    await db.execute('CREATE TABLE products (id TEXT PRIMARY KEY, name TEXT NOT NULL, category TEXT, stockQuantity INTEGER NOT NULL DEFAULT 0, costPrice REAL NOT NULL DEFAULT 0, sellingPrice REAL NOT NULL DEFAULT 0, lowStockThreshold INTEGER NOT NULL DEFAULT 5, barcode TEXT, expiryDate TEXT)');
    await db.execute('CREATE TABLE customers (id TEXT PRIMARY KEY, name TEXT NOT NULL, phone TEXT, email TEXT, notes TEXT, createdAt TEXT NOT NULL)');
    await db.execute('CREATE INDEX idx_customers_name ON customers(name)');
    await db.execute('CREATE TABLE bills (id TEXT PRIMARY KEY, date TEXT NOT NULL, customerName TEXT, discount REAL NOT NULL DEFAULT 0, taxPercent REAL NOT NULL DEFAULT 0)');
    await db.execute('CREATE TABLE bill_items (id INTEGER PRIMARY KEY AUTOINCREMENT, billId TEXT NOT NULL, productId TEXT, productName TEXT NOT NULL, quantity INTEGER NOT NULL, unitPrice REAL NOT NULL, cloudId TEXT, FOREIGN KEY (billId) REFERENCES bills (id) ON DELETE CASCADE)');
    await db.execute('CREATE TABLE bill_returns (id TEXT PRIMARY KEY, billId TEXT NOT NULL, productId TEXT NOT NULL, productName TEXT NOT NULL, unitPrice REAL NOT NULL DEFAULT 0, quantity INTEGER NOT NULL CHECK(quantity > 0), refundAmount REAL NOT NULL, date TEXT NOT NULL, reason TEXT NOT NULL, FOREIGN KEY (billId) REFERENCES bills(id) ON DELETE CASCADE)');
    await db.execute('CREATE INDEX idx_bill_returns_bill_product ON bill_returns(billId, productId)');
    await db.execute('CREATE TABLE suppliers (id TEXT PRIMARY KEY, name TEXT NOT NULL, phone TEXT, totalStockReceivedValue REAL NOT NULL DEFAULT 0, totalPaymentsMade REAL NOT NULL DEFAULT 0)');
    await db.execute("CREATE TABLE supplier_orders (id TEXT PRIMARY KEY, supplierId TEXT NOT NULL, supplierName TEXT NOT NULL, date TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'draft')");
    await db.execute('CREATE TABLE supplier_order_items (id INTEGER PRIMARY KEY AUTOINCREMENT, orderId TEXT NOT NULL, productName TEXT NOT NULL, requiredQuantity INTEGER NOT NULL, estimatedPrice REAL NOT NULL, cloudId TEXT, FOREIGN KEY (orderId) REFERENCES supplier_orders (id) ON DELETE CASCADE)');
    await db.execute("CREATE TABLE daily_sales (id TEXT PRIMARY KEY, date TEXT NOT NULL, billId TEXT, productId TEXT, productName TEXT NOT NULL, costPrice REAL NOT NULL, salePrice REAL NOT NULL, quantity INTEGER NOT NULL DEFAULT 1, source TEXT NOT NULL DEFAULT 'manual')");
    await db.execute('CREATE TABLE expenses (id TEXT PRIMARY KEY, date TEXT NOT NULL, label TEXT NOT NULL, amount REAL NOT NULL)');
    await _createSyncQueue(db);
    await db.execute('CREATE TABLE sync_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
    await _createBranchesTable(db);
    await db.execute('CREATE TABLE supplier_transactions (id TEXT PRIMARY KEY, supplierId TEXT NOT NULL, type TEXT NOT NULL, amount REAL NOT NULL, date TEXT NOT NULL, referenceId TEXT, FOREIGN KEY (supplierId) REFERENCES suppliers(id) ON DELETE CASCADE)');
    await db.execute('CREATE INDEX idx_supplier_transactions_supplier ON supplier_transactions(supplierId, date)');
    await db.execute('CREATE INDEX idx_products_name ON products(name)');
    await db.execute('CREATE INDEX idx_products_barcode ON products(barcode)');
    await db.execute('CREATE INDEX idx_products_expiryDate ON products(expiryDate)');
    await db.execute('CREATE INDEX idx_bill_items_billId ON bill_items(billId)');
    await db.execute('CREATE INDEX idx_sales_date ON daily_sales(date)');
    await db.execute('CREATE INDEX idx_sales_billId ON daily_sales(billId)');
  }
}
