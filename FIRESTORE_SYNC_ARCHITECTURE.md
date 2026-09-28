# Firebase Firestore Sync Architecture
## Offline-First with Sync Queue

---

## 📐 Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│ User Interface (Flutter)                                │
│ - InventoryProvider, PosProvider, etc.                  │
│ - SyncProvider (exposes sync status)                    │
└─────────────────────────────────────────────────────────┘
                        │
        ┌��──────────────┼───────────────┐
        ▼               ▼               ▼
   ┌─────────┐  ┌──────────────┐  ┌────────────────┐
   │ Local   │  │ Sync Queue   │  │ Connectivity   │
   │ SQLite  │  │ Service      │  │ Service        │
   │ DB      │  │              │  │                │
   └────┬────┘  └──────┬───────┘  └────────┬───────┘
        │               │                  │
        └───────────────┼──────────────────┘
                        │
                  ┌─────▼──────┐
                  │ Sync       │
                  │ Service    │
                  │ (Push/Pull)│
                  └─────┬──────┘
                        │
                   ┌────▼──────────┐
                   │ Firebase      │
                   │ Firestore     │
                   │ Cloud         │
                   └───────────────┘
```

---

## 🔄 Data Flow: Offline to Online

### OFFLINE (Device without internet)
```
1. User creates bill
   ↓
2. PosProvider.checkout() called
   ↓
3. Data saved to local SQLite
   ↓
4. SyncQueueService.queueOperation() called
   ↓
5. Operation stored in sync_queue table:
   - Operation: 'create'
   - Table: 'bills'
   - Document ID: 'bill-123'
   - Data: {id, date, customer, items, total}
   - Synced: 0 (not yet synced)
   ↓
6. UI responds normally (no delay)
```

### ONLINE (Device reconnects to internet)
```
1. ConnectivityService detects internet
   ↓
2. Triggers SyncQueueService.syncPendingOperations()
   ↓
3. Loop through sync_queue table where synced=0:
   For each operation:
   a) Get operation data
   b) Push to Firestore at path:
      users/{userId}/bills/bill-123
   c) Mark operation as synced=1
   d) Remove from memory queue
   ↓
4. SyncService.syncFromCloud() pulls latest data:
   - Check Firestore for newer data
   - Merge conflicts (last-write-wins)
   - Update local SQLite
   ↓
5. All devices get notified of changes
```

---

## 📊 Sync Queue Table Schema

```sql
CREATE TABLE sync_queue (
    id TEXT PRIMARY KEY,                    -- Unique operation ID
    operation TEXT NOT NULL,                 -- 'create', 'update', 'delete'
    tableName TEXT NOT NULL,                 -- 'bills', 'products', etc.
    documentId TEXT NOT NULL,                -- Record ID
    data TEXT NOT NULL,                      -- JSON serialized data
    timestamp INTEGER NOT NULL,              -- When operation was queued
    synced INTEGER DEFAULT 0                 -- 0=pending, 1=synced
);
```

**Example rows:**
```
id                      | operation | tableName | documentId | data              | timestamp      | synced
─────────────────────────────────────────────────────────────────────────────────────────────────────────
bills_b1_1695897600000  | create    | bills     | b1         | {id,date,total}   | 1695897600000  | 0
bills_b2_1695897610000  | create    | bills     | b2         | {id,date,total}   | 1695897610000  | 0
products_p1_1695897620  | update    | products  | p1         | {stock:45}        | 1695897620000  | 0
```

---

## 🔐 Firestore Security Rules

```firestore
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Users collection
    match /users/{userId} {
      allow read, write: if request.auth.uid == userId;
      
      // User's subcollections: shop, products, bills, etc.
      match /{document=**} {
        allow read, write: if request.auth.uid == userId;
      }
    }
    
    // Prevent unauthorized access
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

---

## 🔄 Conflict Resolution Strategy

### Scenario: Same product edited on 2 devices offline

**Device A (offline):**
```
Product: Tea
Stock: 50 → 45 (sold 5 units)
Timestamp: 1695897600
```

**Device B (offline):**
```
Product: Tea
Stock: 50 → 48 (received shipment of -2)
Timestamp: 1695897610
```

**When both come online:**
- Device A syncs first: Tea stock = 45 → Firestore
- Device B syncs next: Tea stock = 48 → Firestore (overwrites A)
- Last-Write-Wins (LWW) strategy applies
- Final state: Tea stock = 48 (Device B's version)

**Note:** For critical business logic, consider:
- Add `version` field to detect conflicts
- Use transaction-based syncing
- Implement custom conflict resolution

---

## 📱 Multi-Device Scenario

### Device A (Inventory Management)
```
1. Creates inventory entry
2. Adds to local SQLite
3. Queues to sync_queue
4. Comes online → syncs to Firestore
```

### Device B (Sales/Billing)
```
1. Comes online
2. SyncService.syncFromCloud() pulls from Firestore
3. Sees new inventory from Device A
4. Updates local SQLite
5. Shows updated inventory to user
```

### Device C (Financial Dashboard)
```
1. Always online
2. Auto-syncs from Firestore in real-time
3. Shows live data from all other devices
4. Can also make changes which sync instantly
```

---

## 🚀 Implementation Flow

### Step 1: Initialize in main.dart
```dart
Future<void> _bootstrap() async {
  final auth = context.read<AuthProvider>();
  await auth.checkExistingSession();
  
  if (auth.isLoggedIn) {
    final userId = await FirebaseAuthService.instance.getUserUid();
    
    // Initialize sync services
    await SyncService.instance.init(userId);
    await SyncQueueService.instance.init(userId);
    await ConnectivityService.instance.init(userId);
    
    // Load local data
    await context.read<ShopProvider>().load();
    await context.read<InventoryProvider>().load();
  }
}
```

### Step 2: Wrap write operations with queue
```dart
// OLD:
await db.insert('bills', bill.toMap());

// NEW:
await db.insert('bills', bill.toMap());
if (SyncService.instance.isOnline) {
  await SyncService.instance.queueOfflineOperation(
    operation: 'create',
    tableName: 'bills',
    documentId: bill.id,
    data: bill.toMap(),
  );
}
```

### Step 3: Monitor sync status in UI
```dart
class SyncIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<SyncProvider>(builder: (_, sync, __) {
      if (!sync.isOnline) {
        return Chip(label: Text('Offline'));
      }
      if (sync.isSyncing) {
        return Chip(label: Text('Syncing...'));
      }
      if (sync.pendingOperations > 0) {
        return Chip(label: Text('${sync.pendingOperations} pending'));
      }
      return Chip(label: Text('✓ Synced'));
    });
  }
}
```

---

## 📊 Database Size Optimization

### Sync Queue Cleanup
```dart
// After all synced=1, optionally delete old records
final db = await DBService.instance.database;
await db.delete(
  'sync_queue',
  where: 'synced = ? AND timestamp < ?',
  whereArgs: [1, DateTime.now().subtract(Duration(days: 30)).millisecondsSinceEpoch],
);
```

---

## 🧪 Testing Sync

### Test 1: Create offline, sync online
```
1. Enable Airplane Mode
2. Create bill
3. Create product
4. Verify synced=0 in sync_queue
5. Disable Airplane Mode
6. Watch logs: "[SyncService] Synced: bills/bill-123"
7. Verify synced=1 in database
8. Check Firestore console: data present
```

### Test 2: Multi-device sync
```
1. Device A: Create bill, sync (online)
2. Device B: Open app, login
3. Device B auto-pulls from Firestore
4. Bill from Device A visible on Device B
```

### Test 3: Conflict resolution
```
1. Device A offline: Edit product stock 50→45
2. Device B offline: Edit product stock 50→48
3. Both come online
4. Winner: Last-write-wins
5. Final: stock=48 (or whatever synced last)
```

---

## 📈 Performance Metrics

| Operation | Offline | Online (1st sync) | Online (2nd+) |
|-----------|---------|-------------------|---------------|
| Create bill | <100ms | <100ms | Real-time |
| Sync 100 bills | N/A | ~2s | ~2s |
| Pull from cloud | N/A | ~1s | Instant |
| Queue operation | <50ms | <100ms | N/A |
| Batch write 1000 rows | N/A | ~5s | ~5s |

---

## 🐛 Troubleshooting

### Problem: Sync never completes
**Solution:**
- Check Firebase credentials
- Verify Firestore Security Rules
- Check network connectivity
- Review device logs: `flutter logs | grep SyncService`

### Problem: Conflicts between devices
**Solution:**
- Implement version tracking
- Use transaction-based sync
- Manual conflict UI for user review

### Problem: Sync queue grows indefinitely
**Solution:**
- Check Firestore quota limits
- Clean up old synced records
- Implement automatic cleanup policy

---

## ✅ Production Checklist

- [ ] Firestore Security Rules deployed
- [ ] All tables have sync_queue support
- [ ] Connectivity monitoring active
- [ ] Error handling for sync failures
- [ ] User notification for pending operations
- [ ] Sync cleanup policy (30+ days)
- [ ] Conflict resolution tested
- [ ] Multi-device sync verified
- [ ] Offline mode thoroughly tested
- [ ] Performance benchmarks passed
