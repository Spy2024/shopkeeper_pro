import 'dart:convert';
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

/// Produces a collision-free filename token for a Firebase UID while preserving
/// existing filenames for ordinary Firebase UIDs. Sanitizing unsupported
/// characters to underscores can map different accounts to the same SQLite file.
String databaseFileTokenForUser(String userId) {
  final cleanId = userId.trim();
  if (cleanId.isEmpty) throw ArgumentError('A non-empty user ID is required.');
  if (RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(cleanId)) return cleanId;
  return 'encoded.${base64Url.encode(utf8.encode(cleanId)).replaceAll('=', '')}';
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
    final safeId = databaseFileTokenForUser(cleanId);
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
    final safeId = databaseFileTokenForUser(cleanId);
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
    final safeId = databaseFileTokenForUser(expectedUserId);
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
    final safeId = databaseFileTokenForUser(activeUserId);
    final path = join(dbPath, 'shopkeeper_pro_$safeId.db');
    _db = await _openAt(path);
    return _db!;
  }

  Future<Database> _openAt(String path) async {
    return openDatabase(
      path,
      version: 26,
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
        if (oldVersion < 13) {
          await db.execute('ALTER TABLE bills ADD COLUMN branchId TEXT');
          await db.execute('ALTER TABLE daily_sales ADD COLUMN branchId TEXT');
          await db.execute('ALTER TABLE expenses ADD COLUMN branchId TEXT');
          await db.execute('ALTER TABLE supplier_orders ADD COLUMN branchId TEXT');
          await _createOperationsTables(db);
        }
        if (oldVersion < 14) {
          await db.execute('ALTER TABLE bill_returns ADD COLUMN branchId TEXT');
        }
        if (oldVersion < 15) {
          await db.execute('ALTER TABLE customers ADD COLUMN address TEXT');
          await db.execute('ALTER TABLE shop ADD COLUMN email TEXT');
          await db.execute('ALTER TABLE shop ADD COLUMN website TEXT');
          await db.execute('ALTER TABLE shop ADD COLUMN facebookUrl TEXT');
          await db.execute('ALTER TABLE shop ADD COLUMN instagramUrl TEXT');
          await db.execute('ALTER TABLE shop ADD COLUMN socialUrl TEXT');
        }
        if (oldVersion < 16) {
          await db.execute('ALTER TABLE bills ADD COLUMN customerAddress TEXT');
          await db.execute('ALTER TABLE bills ADD COLUMN customerPhone TEXT');
          await db.execute('ALTER TABLE bills ADD COLUMN customerEmail TEXT');
        }
        if (oldVersion < 17) {
          await db.execute('ALTER TABLE bills ADD COLUMN customerId TEXT');
        }
        if (oldVersion < 18) {
          await db.execute("ALTER TABLE bill_returns ADD COLUMN refundMethod TEXT NOT NULL DEFAULT 'cash'");
        }
        if (oldVersion < 19) {
          await _createMobileShopTables(db);
        }
        if (oldVersion < 20) {
          // v19 databases already have mobile_devices; older schemas create
          // that table in the v19 migration using the current column set.
          if (oldVersion >= 19) {
            await db.execute('ALTER TABLE mobile_devices ADD COLUMN soldBillId TEXT');
          }
          await db.execute('ALTER TABLE bill_items ADD COLUMN mobileDeviceId TEXT');
          await db.execute('ALTER TABLE bill_items ADD COLUMN mobileImei TEXT');
          await db.execute('ALTER TABLE bill_returns ADD COLUMN mobileDeviceId TEXT');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_bill_items_mobile_device ON bill_items(mobileDeviceId)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_bill_returns_mobile_device ON bill_returns(mobileDeviceId)');
        }
        if (oldVersion < 21) {
          await _createMobileRepairFinanceTables(db);
        }
        if (oldVersion < 22) {
          await _createBusinessVerticalTables(db);
          await _ensureColumn(db, 'cargo_jobs', 'trackingToken', 'TEXT');
        }
        if (oldVersion < 23) {
          await _createSnookerTables(db);
    await _createSnookerEquipmentTables(db);
        }
        if (oldVersion < 24) {
          await _ensureColumn(db, 'snooker_payments', 'payerId', 'TEXT');
        }
        if (oldVersion < 25) {
          await _createSnookerEquipmentTables(db);
        }
        if (oldVersion < 26) {
          await db.execute("ALTER TABLE products ADD COLUMN businessAttributes TEXT NOT NULL DEFAULT '{}'");
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

  Future<void> _createOperationsTables(Database db) async {
    await db.execute('CREATE INDEX IF NOT EXISTS idx_bills_branch_date ON bills(branchId, date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_branch_date ON daily_sales(branchId, date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_expenses_branch_date ON expenses(branchId, date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_supplier_orders_branch_date ON supplier_orders(branchId, date)');
    await db.execute("""
      CREATE TABLE IF NOT EXISTS branch_stock (
        branchId TEXT NOT NULL,
        productId TEXT NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 0 CHECK(quantity >= 0),
        updatedAt TEXT NOT NULL,
        PRIMARY KEY (branchId, productId),
        FOREIGN KEY (branchId) REFERENCES branches(id) ON DELETE RESTRICT,
        FOREIGN KEY (productId) REFERENCES products(id) ON DELETE RESTRICT
      )
    """);
    await db.execute("""
      CREATE TABLE IF NOT EXISTS stock_transfers (
        id TEXT PRIMARY KEY,
        fromBranchId TEXT NOT NULL,
        toBranchId TEXT NOT NULL,
        productId TEXT NOT NULL,
        quantity INTEGER NOT NULL CHECK(quantity > 0),
        status TEXT NOT NULL DEFAULT 'completed' CHECK(status IN ('pending','completed','cancelled')),
        createdAt TEXT NOT NULL,
        note TEXT,
        CHECK(fromBranchId != toBranchId),
        FOREIGN KEY (fromBranchId) REFERENCES branches(id) ON DELETE RESTRICT,
        FOREIGN KEY (toBranchId) REFERENCES branches(id) ON DELETE RESTRICT,
        FOREIGN KEY (productId) REFERENCES products(id) ON DELETE RESTRICT
      )
    """);
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_transfers_date ON stock_transfers(createdAt)');
    await db.execute("""
      CREATE TABLE IF NOT EXISTS branch_cash_transactions (
        id TEXT PRIMARY KEY,
        branchId TEXT NOT NULL,
        type TEXT NOT NULL CHECK(type IN ('opening','cash_in','cash_out','sale','refund','expense','transfer_in','transfer_out','adjustment')),
        amount REAL NOT NULL CHECK(amount >= 0),
        date TEXT NOT NULL,
        referenceId TEXT,
        note TEXT,
        FOREIGN KEY (branchId) REFERENCES branches(id) ON DELETE RESTRICT
      )
    """);
    await db.execute('CREATE INDEX IF NOT EXISTS idx_branch_cash_branch_date ON branch_cash_transactions(branchId, date)');
    await db.execute("""
      CREATE TABLE IF NOT EXISTS customer_ledger (
        id TEXT PRIMARY KEY,
        customerId TEXT NOT NULL,
        type TEXT NOT NULL CHECK(type IN ('opening','sale_due','payment','refund','adjustment')),
        amount REAL NOT NULL CHECK(amount >= 0),
        date TEXT NOT NULL,
        referenceId TEXT,
        note TEXT,
        FOREIGN KEY (customerId) REFERENCES customers(id) ON DELETE RESTRICT
      )
    """);
    await db.execute('CREATE INDEX IF NOT EXISTS idx_customer_ledger_customer_date ON customer_ledger(customerId, date)');
    await db.execute("""
      CREATE TABLE IF NOT EXISTS payment_allocations (
        id TEXT PRIMARY KEY,
        billId TEXT NOT NULL,
        method TEXT NOT NULL CHECK(method IN ('cash','card','bank','wallet','credit','other')),
        amount REAL NOT NULL CHECK(amount >= 0),
        reference TEXT,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (billId) REFERENCES bills(id) ON DELETE CASCADE
      )
    """);
    await db.execute('CREATE INDEX IF NOT EXISTS idx_payment_allocations_bill ON payment_allocations(billId)');
  }

  Future<void> _createMobileShopTables(DatabaseExecutor db) async {
    await db.execute("""
      CREATE TABLE IF NOT EXISTS mobile_devices (
        id TEXT PRIMARY KEY,
        deviceType TEXT NOT NULL CHECK(deviceType IN ('new','used')),
        brand TEXT NOT NULL,
        model TEXT NOT NULL,
        variant TEXT,
        color TEXT,
        imei1 TEXT,
        imei2 TEXT,
        serialNumber TEXT,
        conditionGrade TEXT,
        status TEXT NOT NULL DEFAULT 'in_stock'
          CHECK(status IN ('inspection_pending','in_stock','reserved','sold','repair','returned','rejected','written_off')),
        supplierId TEXT,
        sellerName TEXT,
        sellerPhone TEXT,
        purchasePrice REAL NOT NULL DEFAULT 0 CHECK(purchasePrice >= 0),
        repairCost REAL NOT NULL DEFAULT 0 CHECK(repairCost >= 0),
        sellingPrice REAL NOT NULL DEFAULT 0 CHECK(sellingPrice >= 0),
        warrantyMonths INTEGER NOT NULL DEFAULT 0 CHECK(warrantyMonths >= 0),
        purchaseDate TEXT,
        soldAt TEXT,
        soldBillId TEXT,
        branchId TEXT,
        inspectionJson TEXT NOT NULL DEFAULT '{}',
        notes TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    """);
    await db.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_mobile_devices_imei1 ON mobile_devices(imei1) WHERE imei1 IS NOT NULL AND imei1 != ''");
    await db.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_mobile_devices_imei2 ON mobile_devices(imei2) WHERE imei2 IS NOT NULL AND imei2 != ''");
    await db.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_mobile_devices_serial ON mobile_devices(serialNumber) WHERE serialNumber IS NOT NULL AND serialNumber != ''");
    await db.execute("""
      CREATE TRIGGER IF NOT EXISTS trg_mobile_devices_imei_unique_insert
      BEFORE INSERT ON mobile_devices
      WHEN (NEW.imei1 IS NOT NULL AND NEW.imei1 != '' AND EXISTS (
        SELECT 1 FROM mobile_devices
        WHERE imei1 = NEW.imei1 OR imei2 = NEW.imei1
      )) OR (NEW.imei2 IS NOT NULL AND NEW.imei2 != '' AND EXISTS (
        SELECT 1 FROM mobile_devices
        WHERE imei1 = NEW.imei2 OR imei2 = NEW.imei2
      ))
      BEGIN SELECT RAISE(ABORT, 'Duplicate IMEI'); END
    """);
    await db.execute("""
      CREATE TRIGGER IF NOT EXISTS trg_mobile_devices_imei_unique_update
      BEFORE UPDATE OF imei1, imei2 ON mobile_devices
      WHEN (NEW.imei1 IS NOT NULL AND NEW.imei1 != '' AND EXISTS (
        SELECT 1 FROM mobile_devices
        WHERE id != NEW.id AND (imei1 = NEW.imei1 OR imei2 = NEW.imei1)
      )) OR (NEW.imei2 IS NOT NULL AND NEW.imei2 != '' AND EXISTS (
        SELECT 1 FROM mobile_devices
        WHERE id != NEW.id AND (imei1 = NEW.imei2 OR imei2 = NEW.imei2)
      ))
      BEGIN SELECT RAISE(ABORT, 'Duplicate IMEI'); END
    """);
    await db.execute("CREATE INDEX IF NOT EXISTS idx_mobile_devices_status ON mobile_devices(status, deviceType)");
    await db.execute("CREATE INDEX IF NOT EXISTS idx_mobile_devices_model ON mobile_devices(brand, model)");

    await db.execute("""
      CREATE TABLE IF NOT EXISTS mobile_repair_jobs (
        id TEXT PRIMARY KEY,
        jobNumber TEXT NOT NULL UNIQUE,
        customerId TEXT,
        customerName TEXT NOT NULL,
        customerPhone TEXT,
        deviceId TEXT,
        brand TEXT,
        model TEXT,
        imei TEXT,
        reportedIssue TEXT NOT NULL,
        diagnosis TEXT,
        estimateAmount REAL NOT NULL DEFAULT 0 CHECK(estimateAmount >= 0),
        approvedAmount REAL NOT NULL DEFAULT 0 CHECK(approvedAmount >= 0),
        labourCharge REAL NOT NULL DEFAULT 0 CHECK(labourCharge >= 0),
        partsCost REAL NOT NULL DEFAULT 0 CHECK(partsCost >= 0),
        advancePaid REAL NOT NULL DEFAULT 0 CHECK(advancePaid >= 0),
        balanceDue REAL NOT NULL DEFAULT 0 CHECK(balanceDue >= 0),
        status TEXT NOT NULL DEFAULT 'received'
          CHECK(status IN ('received','inspection','estimate_sent','awaiting_approval','in_progress','waiting_for_parts','quality_check','ready','delivered','cancelled','rejected')),
        technicianName TEXT,
        promisedAt TEXT,
        receivedAt TEXT NOT NULL,
        deliveredAt TEXT,
        customerConsent INTEGER NOT NULL DEFAULT 0 CHECK(customerConsent IN (0,1)),
        warrantyDays INTEGER NOT NULL DEFAULT 0 CHECK(warrantyDays >= 0),
        branchId TEXT,
        notes TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        FOREIGN KEY (deviceId) REFERENCES mobile_devices(id) ON DELETE SET NULL
      )
    """);
    await db.execute("CREATE INDEX IF NOT EXISTS idx_mobile_repair_jobs_status ON mobile_repair_jobs(status, receivedAt)");
    await db.execute("CREATE INDEX IF NOT EXISTS idx_mobile_repair_jobs_customer ON mobile_repair_jobs(customerId, receivedAt)");
    await db.execute("CREATE INDEX IF NOT EXISTS idx_mobile_repair_jobs_imei ON mobile_repair_jobs(imei)");

    await db.execute("""
      CREATE TABLE IF NOT EXISTS mobile_repair_job_parts (
        id TEXT PRIMARY KEY,
        jobId TEXT NOT NULL,
        productId TEXT,
        partName TEXT NOT NULL,
        quantity INTEGER NOT NULL CHECK(quantity > 0),
        unitCost REAL NOT NULL DEFAULT 0 CHECK(unitCost >= 0),
        unitPrice REAL NOT NULL DEFAULT 0 CHECK(unitPrice >= 0),
        createdAt TEXT NOT NULL,
        FOREIGN KEY (jobId) REFERENCES mobile_repair_jobs(id) ON DELETE CASCADE,
        FOREIGN KEY (productId) REFERENCES products(id) ON DELETE SET NULL
      )
    """);
    await db.execute("CREATE INDEX IF NOT EXISTS idx_mobile_repair_job_parts_job ON mobile_repair_job_parts(jobId)");
  }

  Future<void> _createMobileRepairFinanceTables(DatabaseExecutor db) async {
    await db.execute("""
      CREATE TABLE IF NOT EXISTS mobile_repair_payments (
        id TEXT PRIMARY KEY,
        jobId TEXT NOT NULL,
        amount REAL NOT NULL CHECK(amount > 0),
        method TEXT NOT NULL CHECK(method IN ('cash','card','bank','wallet','credit','other')),
        reference TEXT,
        paidAt TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (jobId) REFERENCES mobile_repair_jobs(id) ON DELETE CASCADE
      )
    """);
    await db.execute('CREATE INDEX IF NOT EXISTS idx_mobile_repair_payments_job_date ON mobile_repair_payments(jobId, paidAt)');
    await db.execute("""
      CREATE TABLE IF NOT EXISTS mobile_repair_warranties (
        id TEXT PRIMARY KEY,
        jobId TEXT NOT NULL,
        deviceId TEXT,
        customerId TEXT,
        customerName TEXT NOT NULL,
        warrantyType TEXT NOT NULL CHECK(warrantyType IN ('repair','device')),
        startsAt TEXT NOT NULL,
        expiresAt TEXT NOT NULL,
        terms TEXT,
        status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active','claimed','expired','void')),
        createdAt TEXT NOT NULL,
        FOREIGN KEY (jobId) REFERENCES mobile_repair_jobs(id) ON DELETE CASCADE,
        FOREIGN KEY (deviceId) REFERENCES mobile_devices(id) ON DELETE SET NULL
      )
    """);
    await db.execute('CREATE INDEX IF NOT EXISTS idx_mobile_repair_warranties_expiry ON mobile_repair_warranties(status, expiresAt)');
    await db.execute("""
      CREATE TABLE IF NOT EXISTS mobile_repair_warranty_claims (
        id TEXT PRIMARY KEY,
        warrantyId TEXT NOT NULL,
        description TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'open' CHECK(status IN ('open','approved','rejected','resolved')),
        resolution TEXT,
        createdAt TEXT NOT NULL,
        resolvedAt TEXT,
        FOREIGN KEY (warrantyId) REFERENCES mobile_repair_warranties(id) ON DELETE CASCADE
      )
    """);
    await db.execute('CREATE INDEX IF NOT EXISTS idx_mobile_repair_warranty_claims_warranty ON mobile_repair_warranty_claims(warrantyId, createdAt)');
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

  Future<void> _ensureColumn(DatabaseExecutor db, String table, String column, String type) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    if (!columns.any((entry) => entry['name'] == column)) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    }
  }

  Future<void> _createBusinessVerticalTables(DatabaseExecutor db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS payments (id TEXT PRIMARY KEY, billId TEXT NOT NULL, method TEXT NOT NULL, amount REAL NOT NULL, reference TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS returns (id TEXT PRIMARY KEY, billId TEXT NOT NULL, date TEXT NOT NULL, customerName TEXT, refundAmount REAL NOT NULL, reason TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS return_items (id TEXT PRIMARY KEY, returnId TEXT NOT NULL, productId TEXT, productName TEXT NOT NULL, imei TEXT, quantity INTEGER NOT NULL, unitPrice REAL NOT NULL)');
    await db.execute('CREATE TABLE IF NOT EXISTS branch_cash_entries (id TEXT PRIMARY KEY, branchId TEXT NOT NULL, date TEXT NOT NULL, type TEXT NOT NULL, amount REAL NOT NULL, note TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS product_variants (id TEXT PRIMARY KEY, productId TEXT NOT NULL, size TEXT, color TEXT, sku TEXT, quantity INTEGER NOT NULL DEFAULT 0)');
    await db.execute('CREATE TABLE IF NOT EXISTS restaurant_tables (id TEXT PRIMARY KEY, name TEXT NOT NULL, capacity INTEGER NOT NULL DEFAULT 2, status TEXT NOT NULL DEFAULT \'available\')');
    await db.execute('CREATE TABLE IF NOT EXISTS restaurant_orders (id TEXT PRIMARY KEY, tableId TEXT, status TEXT NOT NULL DEFAULT \'open\', total REAL NOT NULL DEFAULT 0, createdAt TEXT NOT NULL)');
    await db.execute('CREATE TABLE IF NOT EXISTS restaurant_order_payments (id TEXT PRIMARY KEY, orderId TEXT NOT NULL, method TEXT NOT NULL, amount REAL NOT NULL, reference TEXT, paidAt TEXT NOT NULL)');
    await db.execute('CREATE TABLE IF NOT EXISTS restaurant_menu_items (id TEXT PRIMARY KEY, name TEXT NOT NULL, category TEXT, price REAL NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1)');
    await db.execute('CREATE TABLE IF NOT EXISTS restaurant_order_items (id TEXT PRIMARY KEY, orderId TEXT NOT NULL, menuItemId TEXT NOT NULL, quantity INTEGER NOT NULL, unitPrice REAL NOT NULL, notes TEXT, kitchenStatus TEXT NOT NULL DEFAULT \'queued\')');
    await db.execute('CREATE TABLE IF NOT EXISTS vehicle_records (id TEXT PRIMARY KEY, type TEXT NOT NULL, make TEXT, model TEXT, registrationNumber TEXT, vin TEXT, status TEXT NOT NULL DEFAULT \'in_stock\', purchasePrice REAL NOT NULL DEFAULT 0, salePrice REAL NOT NULL DEFAULT 0)');
    await db.execute('CREATE TABLE IF NOT EXISTS vehicle_transactions (id TEXT PRIMARY KEY, vehicleId TEXT NOT NULL, type TEXT NOT NULL, partyName TEXT, transactionDate TEXT NOT NULL, amount REAL NOT NULL, notes TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS transport_routes (id TEXT PRIMARY KEY, name TEXT NOT NULL, origin TEXT, destination TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS transport_tickets (id TEXT PRIMARY KEY, routeId TEXT NOT NULL, passengerName TEXT NOT NULL, seatNumber TEXT, travelDate TEXT NOT NULL, fare REAL NOT NULL, status TEXT NOT NULL DEFAULT \'booked\')');
    await db.execute('CREATE TABLE IF NOT EXISTS cargo_jobs (id TEXT PRIMARY KEY, routeId TEXT, customerName TEXT NOT NULL, loadDescription TEXT, weight REAL NOT NULL DEFAULT 0, freightAmount REAL NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT \'created\', trackingToken TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS cargo_status_history (id TEXT PRIMARY KEY, cargoId TEXT NOT NULL, status TEXT NOT NULL, location TEXT, note TEXT, recordedAt TEXT NOT NULL)');
    await db.execute('CREATE TABLE IF NOT EXISTS service_jobs (id TEXT PRIMARY KEY, customerName TEXT NOT NULL, deviceOrVehicle TEXT, issue TEXT NOT NULL, status TEXT NOT NULL DEFAULT \'received\', estimatedCost REAL NOT NULL DEFAULT 0, finalCost REAL NOT NULL DEFAULT 0, createdAt TEXT NOT NULL)');
    await db.execute('CREATE TABLE IF NOT EXISTS spare_part_compatibility (id TEXT PRIMARY KEY, productId TEXT NOT NULL, partType TEXT NOT NULL, make TEXT, model TEXT, yearFrom INTEGER, yearTo INTEGER, engineCode TEXT, notes TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS school_students (id TEXT PRIMARY KEY, name TEXT NOT NULL, guardianName TEXT, phone TEXT, className TEXT, admissionDate TEXT NOT NULL, status TEXT NOT NULL DEFAULT \'active\')');
    await db.execute('CREATE TABLE IF NOT EXISTS school_fees (id TEXT PRIMARY KEY, studentId TEXT NOT NULL, dueDate TEXT NOT NULL, amount REAL NOT NULL, paidAmount REAL NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT \'due\', note TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS clinic_patients (id TEXT PRIMARY KEY, name TEXT NOT NULL, phone TEXT, dateOfBirth TEXT, notes TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS clinic_appointments (id TEXT PRIMARY KEY, patientId TEXT NOT NULL, appointmentAt TEXT NOT NULL, clinician TEXT, reason TEXT, status TEXT NOT NULL DEFAULT \'scheduled\', fee REAL NOT NULL DEFAULT 0, paidAmount REAL NOT NULL DEFAULT 0)');
    await db.execute('CREATE TABLE IF NOT EXISTS salon_services (id TEXT PRIMARY KEY, name TEXT NOT NULL, durationMinutes INTEGER NOT NULL DEFAULT 30, price REAL NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1)');
    await db.execute('CREATE TABLE IF NOT EXISTS salon_bookings (id TEXT PRIMARY KEY, customerName TEXT NOT NULL, phone TEXT, serviceId TEXT, staffName TEXT, bookingAt TEXT NOT NULL, status TEXT NOT NULL DEFAULT \'booked\', amount REAL NOT NULL DEFAULT 0)');
    await db.execute('CREATE TABLE IF NOT EXISTS farm_plots (id TEXT PRIMARY KEY, name TEXT NOT NULL, area REAL NOT NULL DEFAULT 0, areaUnit TEXT NOT NULL DEFAULT \'acre\', crop TEXT, season TEXT, status TEXT NOT NULL DEFAULT \'active\')');
    await db.execute('CREATE TABLE IF NOT EXISTS farm_activities (id TEXT PRIMARY KEY, plotId TEXT NOT NULL, activityType TEXT NOT NULL, activityDate TEXT NOT NULL, inputName TEXT, quantity REAL NOT NULL DEFAULT 0, cost REAL NOT NULL DEFAULT 0, notes TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS construction_projects (id TEXT PRIMARY KEY, name TEXT NOT NULL, clientName TEXT, location TEXT, budget REAL NOT NULL DEFAULT 0, spent REAL NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT \'planned\', startDate TEXT, dueDate TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS construction_tasks (id TEXT PRIMARY KEY, projectId TEXT NOT NULL, title TEXT NOT NULL, assignedTo TEXT, status TEXT NOT NULL DEFAULT \'todo\', cost REAL NOT NULL DEFAULT 0, dueDate TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS public_service_cases (id TEXT PRIMARY KEY, caseNumber TEXT NOT NULL, applicantName TEXT NOT NULL, serviceType TEXT NOT NULL, openedAt TEXT NOT NULL, status TEXT NOT NULL DEFAULT \'open\', fee REAL NOT NULL DEFAULT 0, notes TEXT)');
  }

  Future<void> _createSnookerEquipmentTables(DatabaseExecutor db) async {
    await db.execute("""
      CREATE TABLE IF NOT EXISTS snooker_inventory_items (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        category TEXT NOT NULL CHECK(category IN ('chalk','tip','glove','other')),
        unit TEXT NOT NULL DEFAULT 'piece',
        quantity REAL NOT NULL DEFAULT 0 CHECK(quantity >= 0),
        minimumQuantity REAL NOT NULL DEFAULT 0 CHECK(minimumQuantity >= 0),
        updatedAt TEXT NOT NULL
      )
    """);
    await db.execute('CREATE INDEX IF NOT EXISTS idx_snooker_inventory_category ON snooker_inventory_items(category)');
    await db.execute("""
      CREATE TABLE IF NOT EXISTS snooker_equipment_assets (
        id TEXT PRIMARY KEY,
        assetType TEXT NOT NULL CHECK(assetType IN ('cue','ball_set','locker')),
        assetNumber TEXT NOT NULL,
        name TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'available'
          CHECK(status IN ('available','in_use','repair','missing','retired')),
        assignedToName TEXT,
        assignedPlayerId TEXT,
        lockerAssetId TEXT,
        tableId TEXT,
        notes TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        UNIQUE(assetType, assetNumber),
        FOREIGN KEY (assignedPlayerId) REFERENCES snooker_players(id) ON DELETE SET NULL,
        FOREIGN KEY (lockerAssetId) REFERENCES snooker_equipment_assets(id) ON DELETE SET NULL,
        FOREIGN KEY (tableId) REFERENCES snooker_tables(id) ON DELETE SET NULL
      )
    """);
    await db.execute('CREATE INDEX IF NOT EXISTS idx_snooker_assets_type_status ON snooker_equipment_assets(assetType, status)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_snooker_assets_assignee ON snooker_equipment_assets(assignedToName)');
    await db.execute("""
      CREATE TABLE IF NOT EXISTS snooker_equipment_movements (
        id TEXT PRIMARY KEY,
        assetId TEXT,
        inventoryItemId TEXT,
        movementType TEXT NOT NULL CHECK(movementType IN ('opening_stock','purchase','issue','return','consume','damage','missing','repair','repair_return','adjustment','retire')),
        quantity REAL NOT NULL,
        personName TEXT,
        fromLocation TEXT,
        toLocation TEXT,
        note TEXT,
        occurredAt TEXT NOT NULL,
        actorId TEXT,
        CHECK((assetId IS NOT NULL AND inventoryItemId IS NULL) OR
              (assetId IS NULL AND inventoryItemId IS NOT NULL)),
        FOREIGN KEY (assetId) REFERENCES snooker_equipment_assets(id) ON DELETE RESTRICT,
        FOREIGN KEY (inventoryItemId) REFERENCES snooker_inventory_items(id) ON DELETE RESTRICT
      )
    """);
    await db.execute('CREATE INDEX IF NOT EXISTS idx_snooker_equipment_movements_date ON snooker_equipment_movements(occurredAt)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_snooker_equipment_movements_asset ON snooker_equipment_movements(assetId)');
  }

  /// Snooker club records are stored separately from ordinary POS bills so
  /// game fees, refreshment sales and cash receipts cannot be double-counted.
  Future<void> _createSnookerTables(DatabaseExecutor db) async {
    await db.execute("""
      CREATE TABLE IF NOT EXISTS snooker_settings (
        id TEXT PRIMARY KEY,
        key TEXT NOT NULL UNIQUE,
        value TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    """);
    await db.execute("""
      CREATE TABLE IF NOT EXISTS snooker_tables (
        id TEXT PRIMARY KEY,
        tableNumber INTEGER NOT NULL UNIQUE CHECK(tableNumber > 0),
        name TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'available'
          CHECK(status IN ('available','occupied','maintenance')),
        activeGameId TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    """);
    await db.execute('CREATE INDEX IF NOT EXISTS idx_snooker_tables_status ON snooker_tables(status)');
    await db.execute("""
      CREATE TABLE IF NOT EXISTS snooker_players (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        normalizedName TEXT NOT NULL UNIQUE,
        phone TEXT,
        notes TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    """);
    await db.execute('CREATE INDEX IF NOT EXISTS idx_snooker_players_name ON snooker_players(name COLLATE NOCASE)');
    await db.execute("""
      CREATE TABLE IF NOT EXISTS snooker_games (
        id TEXT PRIMARY KEY,
        tableId TEXT NOT NULL,
        playerAId TEXT NOT NULL,
        playerBId TEXT NOT NULL,
        playerAName TEXT NOT NULL,
        playerBName TEXT NOT NULL,
        winnerId TEXT,
        status TEXT NOT NULL DEFAULT 'active'
          CHECK(status IN ('active','completed','cancelled')),
        startedAt TEXT NOT NULL,
        endedAt TEXT,
        createdBy TEXT,
        updatedAt TEXT NOT NULL,
        CHECK(playerAId != playerBId),
        FOREIGN KEY (tableId) REFERENCES snooker_tables(id) ON DELETE RESTRICT,
        FOREIGN KEY (playerAId) REFERENCES snooker_players(id) ON DELETE RESTRICT,
        FOREIGN KEY (playerBId) REFERENCES snooker_players(id) ON DELETE RESTRICT,
        FOREIGN KEY (winnerId) REFERENCES snooker_players(id) ON DELETE RESTRICT
      )
    """);
    await db.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_snooker_one_active_game_per_table ON snooker_games(tableId) WHERE status = 'active'");
    await db.execute('CREATE INDEX IF NOT EXISTS idx_snooker_games_started ON snooker_games(startedAt)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_snooker_games_status ON snooker_games(status)');
    await db.execute("""
      CREATE TABLE IF NOT EXISTS snooker_game_fees (
        id TEXT PRIMARY KEY,
        gameId TEXT NOT NULL UNIQUE,
        feeAmount REAL NOT NULL CHECK(feeAmount >= 0),
        discountAmount REAL NOT NULL DEFAULT 0 CHECK(discountAmount >= 0),
        finalAmount REAL NOT NULL CHECK(finalAmount >= 0),
        createdAt TEXT NOT NULL,
        FOREIGN KEY (gameId) REFERENCES snooker_games(id) ON DELETE RESTRICT
      )
    """);
    await db.execute("""
      CREATE TABLE IF NOT EXISTS snooker_payments (
        id TEXT PRIMARY KEY,
        gameId TEXT NOT NULL,
        payerId TEXT,
        amount REAL NOT NULL CHECK(amount > 0),
        method TEXT NOT NULL CHECK(method IN ('cash','bank','card','wallet','other')),
        type TEXT NOT NULL CHECK(type IN ('payment','refund')),
        reference TEXT,
        idempotencyKey TEXT NOT NULL UNIQUE,
        receivedAt TEXT NOT NULL,
        receivedBy TEXT,
        note TEXT,
        FOREIGN KEY (gameId) REFERENCES snooker_games(id) ON DELETE RESTRICT
      )
    """);
    await db.execute('CREATE INDEX IF NOT EXISTS idx_snooker_payments_game_date ON snooker_payments(gameId, receivedAt)');
    await db.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_snooker_payment_reference ON snooker_payments(method, reference) WHERE type = 'payment' AND reference IS NOT NULL AND length(trim(reference)) > 0");
    await db.execute("""
      CREATE TABLE IF NOT EXISTS snooker_expenses (
        id TEXT PRIMARY KEY,
        category TEXT NOT NULL,
        amount REAL NOT NULL CHECK(amount > 0),
        paymentMethod TEXT NOT NULL DEFAULT 'cash'
          CHECK(paymentMethod IN ('cash','bank','card','wallet','other')),
        occurredAt TEXT NOT NULL,
        note TEXT,
        createdBy TEXT,
        idempotencyKey TEXT NOT NULL UNIQUE
      )
    """);
    await db.execute('CREATE INDEX IF NOT EXISTS idx_snooker_expenses_date ON snooker_expenses(occurredAt)');
    await db.execute("""
      CREATE TABLE IF NOT EXISTS snooker_cash_sessions (
        id TEXT PRIMARY KEY,
        openingCash REAL NOT NULL CHECK(openingCash >= 0),
        expectedClosingCash REAL,
        actualClosingCash REAL,
        difference REAL,
        openedAt TEXT NOT NULL,
        closedAt TEXT,
        openedBy TEXT,
        closedBy TEXT,
        note TEXT
      )
    """);
    await db.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_snooker_single_open_cash_session ON snooker_cash_sessions((1)) WHERE closedAt IS NULL");
    await db.execute("""
      CREATE TABLE IF NOT EXISTS snooker_game_events (
        id TEXT PRIMARY KEY,
        gameId TEXT NOT NULL,
        eventType TEXT NOT NULL CHECK(eventType IN ('started','completed','cancelled','result_corrected')),
        previousValue TEXT,
        newValue TEXT,
        reason TEXT,
        actorId TEXT,
        occurredAt TEXT NOT NULL,
        idempotencyKey TEXT NOT NULL UNIQUE,
        FOREIGN KEY (gameId) REFERENCES snooker_games(id) ON DELETE RESTRICT
      )
    """);
    await db.execute('CREATE INDEX IF NOT EXISTS idx_snooker_game_events_game_date ON snooker_game_events(gameId, occurredAt)');
  }

  Future<void> _createSchema(Database db) async {
    await db.execute("CREATE TABLE shop (id TEXT PRIMARY KEY, name TEXT NOT NULL, address TEXT, phone TEXT, taxNumber TEXT, email TEXT, website TEXT, facebookUrl TEXT, instagramUrl TEXT, socialUrl TEXT, logoPath TEXT, businessType TEXT NOT NULL DEFAULT 'general_retail')");
    await db.execute("CREATE TABLE products (id TEXT PRIMARY KEY, name TEXT NOT NULL, category TEXT, stockQuantity INTEGER NOT NULL DEFAULT 0, costPrice REAL NOT NULL DEFAULT 0, sellingPrice REAL NOT NULL DEFAULT 0, lowStockThreshold INTEGER NOT NULL DEFAULT 5, barcode TEXT, expiryDate TEXT, businessAttributes TEXT NOT NULL DEFAULT '{}')");
    await db.execute('CREATE TABLE customers (id TEXT PRIMARY KEY, name TEXT NOT NULL, phone TEXT, email TEXT, address TEXT, notes TEXT, createdAt TEXT NOT NULL)');
    await db.execute('CREATE INDEX idx_customers_name ON customers(name)');
    await db.execute('CREATE TABLE bills (id TEXT PRIMARY KEY, date TEXT NOT NULL, customerName TEXT, customerId TEXT, customerAddress TEXT, customerPhone TEXT, customerEmail TEXT, discount REAL NOT NULL DEFAULT 0, taxPercent REAL NOT NULL DEFAULT 0, branchId TEXT)');
    await db.execute('CREATE TABLE bill_items (id INTEGER PRIMARY KEY AUTOINCREMENT, billId TEXT NOT NULL, productId TEXT, mobileDeviceId TEXT, mobileImei TEXT, productName TEXT NOT NULL, quantity INTEGER NOT NULL, unitPrice REAL NOT NULL, cloudId TEXT, FOREIGN KEY (billId) REFERENCES bills (id) ON DELETE CASCADE)');
    await db.execute("CREATE TABLE bill_returns (id TEXT PRIMARY KEY, billId TEXT NOT NULL, productId TEXT NOT NULL, mobileDeviceId TEXT, productName TEXT NOT NULL, unitPrice REAL NOT NULL DEFAULT 0, quantity INTEGER NOT NULL CHECK(quantity > 0), refundAmount REAL NOT NULL, refundMethod TEXT NOT NULL DEFAULT 'cash', date TEXT NOT NULL, reason TEXT NOT NULL, branchId TEXT, FOREIGN KEY (billId) REFERENCES bills(id) ON DELETE CASCADE)");
    await db.execute('CREATE INDEX idx_bill_returns_bill_product ON bill_returns(billId, productId)');
    await db.execute('CREATE TABLE suppliers (id TEXT PRIMARY KEY, name TEXT NOT NULL, phone TEXT, totalStockReceivedValue REAL NOT NULL DEFAULT 0, totalPaymentsMade REAL NOT NULL DEFAULT 0)');
    await db.execute("CREATE TABLE supplier_orders (id TEXT PRIMARY KEY, supplierId TEXT NOT NULL, supplierName TEXT NOT NULL, date TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'draft', branchId TEXT)");
    await db.execute('CREATE TABLE supplier_order_items (id INTEGER PRIMARY KEY AUTOINCREMENT, orderId TEXT NOT NULL, productName TEXT NOT NULL, requiredQuantity INTEGER NOT NULL, estimatedPrice REAL NOT NULL, cloudId TEXT, FOREIGN KEY (orderId) REFERENCES supplier_orders (id) ON DELETE CASCADE)');
    await db.execute("CREATE TABLE daily_sales (id TEXT PRIMARY KEY, date TEXT NOT NULL, billId TEXT, productId TEXT, productName TEXT NOT NULL, costPrice REAL NOT NULL, salePrice REAL NOT NULL, quantity INTEGER NOT NULL DEFAULT 1, source TEXT NOT NULL DEFAULT 'manual', branchId TEXT)");
    await db.execute('CREATE TABLE expenses (id TEXT PRIMARY KEY, date TEXT NOT NULL, label TEXT NOT NULL, amount REAL NOT NULL, branchId TEXT)');
    await _createSyncQueue(db);
    await db.execute('CREATE TABLE sync_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
    await _createBranchesTable(db);
    await _createOperationsTables(db);
    await _createMobileShopTables(db);
    await _createMobileRepairFinanceTables(db);
    await _createBusinessVerticalTables(db);
    await _createSnookerTables(db);
    await _createSnookerEquipmentTables(db);
    await db.execute('CREATE TABLE supplier_transactions (id TEXT PRIMARY KEY, supplierId TEXT NOT NULL, type TEXT NOT NULL, amount REAL NOT NULL, date TEXT NOT NULL, referenceId TEXT, FOREIGN KEY (supplierId) REFERENCES suppliers(id) ON DELETE CASCADE)');
    await db.execute('CREATE INDEX idx_supplier_transactions_supplier ON supplier_transactions(supplierId, date)');
    await db.execute('CREATE INDEX idx_products_name ON products(name)');
    await db.execute('CREATE INDEX idx_products_barcode ON products(barcode)');
    await db.execute('CREATE INDEX idx_products_expiryDate ON products(expiryDate)');
    await db.execute('CREATE INDEX idx_bill_items_billId ON bill_items(billId)');
    await db.execute('CREATE INDEX idx_bill_items_mobile_device ON bill_items(mobileDeviceId)');
    await db.execute('CREATE INDEX idx_bill_returns_mobile_device ON bill_returns(mobileDeviceId)');
    await db.execute('CREATE INDEX idx_sales_date ON daily_sales(date)');
    await db.execute('CREATE INDEX idx_sales_billId ON daily_sales(billId)');
  }
}