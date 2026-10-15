import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DBService {
  DBService._internal();
  static final DBService instance = DBService._internal();
  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), 'shopkeeper_pro.db');
    return openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async => _createSchema(db),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
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
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE sync_queue ADD COLUMN attempts INTEGER NOT NULL DEFAULT 0');
          await db.execute('ALTER TABLE sync_queue ADD COLUMN nextRetryAt INTEGER');
          await db.execute('ALTER TABLE sync_queue ADD COLUMN lastError TEXT');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS sync_metadata (
              tableName TEXT NOT NULL,
              documentId TEXT NOT NULL,
              updatedAt INTEGER NOT NULL,
              PRIMARY KEY (tableName, documentId)
            )
          ''');
        }
      },
    );
  }

  Future<void> resetForTests() async {
    final path = join(await getDatabasesPath(), 'shopkeeper_pro.db');
    await _db?.close();
    _db = null;
    await deleteDatabase(path);
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('CREATE TABLE shop (id TEXT PRIMARY KEY, name TEXT NOT NULL, address TEXT NOT NULL, phone TEXT NOT NULL, taxNumber TEXT, logoPath TEXT)');
    await db.execute('CREATE TABLE products (id TEXT PRIMARY KEY, name TEXT NOT NULL, category TEXT NOT NULL, stockQuantity INTEGER NOT NULL DEFAULT 0, costPrice REAL NOT NULL DEFAULT 0, sellingPrice REAL NOT NULL DEFAULT 0, lowStockThreshold INTEGER NOT NULL DEFAULT 5)');
    await db.execute('CREATE TABLE bills (id TEXT PRIMARY KEY, date TEXT NOT NULL, customerName TEXT, discount REAL NOT NULL DEFAULT 0, taxPercent REAL NOT NULL DEFAULT 0)');
    await db.execute('CREATE TABLE bill_items (id INTEGER PRIMARY KEY AUTOINCREMENT, billId TEXT NOT NULL, productName TEXT NOT NULL, quantity INTEGER NOT NULL, unitPrice REAL NOT NULL, FOREIGN KEY (billId) REFERENCES bills(id) ON DELETE CASCADE)');
    await db.execute('CREATE TABLE suppliers (id TEXT PRIMARY KEY, name TEXT NOT NULL, phone TEXT NOT NULL, totalStockReceivedValue REAL NOT NULL DEFAULT 0, totalPaymentsMade REAL NOT NULL DEFAULT 0)');
    await db.execute('CREATE TABLE supplier_orders (id TEXT PRIMARY KEY, supplierId TEXT NOT NULL, supplierName TEXT NOT NULL, date TEXT NOT NULL, status TEXT NOT NULL DEFAULT "draft")');
    await db.execute('CREATE TABLE supplier_order_items (id INTEGER PRIMARY KEY AUTOINCREMENT, orderId TEXT NOT NULL, productName TEXT NOT NULL, requiredQuantity INTEGER NOT NULL, estimatedPrice REAL NOT NULL, FOREIGN KEY (orderId) REFERENCES supplier_orders(id) ON DELETE CASCADE)');
    await db.execute('CREATE TABLE daily_sales (id TEXT PRIMARY KEY, date TEXT NOT NULL, productName TEXT NOT NULL, costPrice REAL NOT NULL, salePrice REAL NOT NULL)');
    await db.execute('CREATE TABLE expenses (id TEXT PRIMARY KEY, date TEXT NOT NULL, label TEXT NOT NULL, amount REAL NOT NULL)');
    await db.execute('CREATE TABLE sync_queue (id TEXT PRIMARY KEY, operation TEXT NOT NULL, tableName TEXT NOT NULL, documentId TEXT NOT NULL, data TEXT NOT NULL, timestamp INTEGER NOT NULL, synced INTEGER NOT NULL DEFAULT 0, attempts INTEGER NOT NULL DEFAULT 0, nextRetryAt INTEGER, lastError TEXT)');
    await db.execute('CREATE TABLE sync_metadata (tableName TEXT NOT NULL, documentId TEXT NOT NULL, updatedAt INTEGER NOT NULL, PRIMARY KEY (tableName, documentId))');
  }
}
