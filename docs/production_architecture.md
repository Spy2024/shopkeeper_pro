# Production Architecture Blueprint

## 1. Recommended stack
- Flutter + Dart
- Firebase Authentication
- Firestore Database
- Firebase Storage
- SQLite local cache
- PDF + printing
- Share + WhatsApp export

## 2. Auth architecture
Use Firebase Phone Auth or a custom backend auth service.

### Flow
1. User enters phone number
2. OTP is sent
3. OTP is verified
4. User profile is created in Firestore
5. Shop is linked to the user
6. Secure session is stored

### Required fields
- uid
- phone
- displayName
- createdAt
- updatedAt

## 3. Firestore schema

### users
```json
{
  "id": "user_123",
  "phone": "+923001234567",
  "displayName": "Ali",
  "createdAt": "2026-09-29T10:00:00Z",
  "updatedAt": "2026-09-29T10:00:00Z"
}
```

### shops
```json
{
  "id": "shop_001",
  "ownerUserId": "user_123",
  "name": "Ali Mart",
  "address": "Main Market Lahore",
  "phone": "+923001234567",
  "taxNumber": "1234567",
  "logoPath": "shops/shop_001/logo.png",
  "createdAt": "2026-09-29T10:00:00Z"
}
```

### products
```json
{
  "id": "prod_001",
  "shopId": "shop_001",
  "name": "Rice 10kg",
  "category": "Groceries",
  "costPrice": 850,
  "sellingPrice": 950,
  "stockQuantity": 32,
  "sku": "RICE-10",
  "createdAt": "2026-09-29T10:00:00Z",
  "updatedAt": "2026-09-29T10:00:00Z"
}
```

### customers
```json
{
  "id": "cust_001",
  "shopId": "shop_001",
  "name": "Hassan",
  "phone": "+923012345678",
  "address": "Township",
  "totalDue": 1200,
  "createdAt": "2026-09-29T10:00:00Z"
}
```

### bills
```json
{
  "id": "bill_001",
  "shopId": "shop_001",
  "customerId": "cust_001",
  "customerName": "Hassan",
  "date": "2026-09-29T12:00:00Z",
  "subtotal": 2500,
  "discount": 100,
  "taxPercent": 5,
  "taxAmount": 120,
  "grandTotal": 2520,
  "status": "paid",
  "createdAt": "2026-09-29T12:00:00Z"
}
```

### billItems
```json
{
  "id": "bill_item_001",
  "billId": "bill_001",
  "productId": "prod_001",
  "productName": "Rice 10kg",
  "quantity": 2,
  "unitPrice": 950,
  "total": 1900
}
```

## 4. Local SQLite + sync strategy
- SQLite is local cache and offline store
- Firestore is system of record
- Sync queue stores pending writes when offline
- Data is uploaded automatically when connection is restored
- Conflicts are resolved using updatedAt timestamp

### Sync queue schema
```json
{
  "id": "sync_001",
  "entityType": "products",
  "entityId": "prod_001",
  "action": "create",
  "payload": "{...}",
  "createdAt": "2026-09-29T12:00:00Z",
  "syncedAt": null
}
```

## 5. Invoice upgrade requirements
- shop logo embedding
- invoice number sequence
- print preview
- thermal printer support
- A4 invoice support
- branded header and footer
- tax and discount breakdown

## 6. Production roadmap
1. Firebase auth setup
2. Firestore schema
3. SQLite sync queue
4. Invoice branding
5. Reports and analytics
6. Testing + release

## 7. Best recommendation
For this project, the best production stack is:
- Flutter
- Firebase Auth
- Firestore
- Firebase Storage
- SQLite cache
- PDF + print
- sync service
