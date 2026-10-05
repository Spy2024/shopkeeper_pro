import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DBService {
  DBService._internal();
  static final DBService instance = DBService._internal();
  Database? _db;

  Future<Database> get database async => _db ??= await _initDb();

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'shopkeeper_pro.db');
    return openDatabase(
      path,
      version: 4,
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
    await db.execute("CREATE TABLE daily_sales (id TEXT PRIMARY KEY, date TEXT NOT NULL, billId TEXT, productId TEXT, productName TEXT NOT NULL, costPrice REAL NOT NULL, salePrice REAL NOT NULL, source TEXT NOT NULL DEFAULT 'manual')");
    await db.execute('CREATE TABLE expenses (id TEXT PRIMARY KEY, date TEXT NOT NULL, label TEXT NOT NULL, amount REAL NOT NULL)');
    await _createSyncQueue(db);
    await db.execute('CREATE INDEX idx_products_name ON products(name)');
    await db.execute('CREATE INDEX idx_bill_items_billId ON bill_items(billId)');
    await db.execute('CREATE INDEX idx_sales_date ON daily_sales(date)');
    await db.execute('CREATE INDEX idx_sales_billId ON daily_sales(billId)');
  }
}
