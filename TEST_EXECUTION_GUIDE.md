# 🧪 Shopkeeper Pro - Microlevel Test Execution Guide
## Complete Testing from Start to End

---

## ✅ TEST CHECKLIST

### TEST 1: Authentication Flow
**Status:** ✅ READY

```
✓ Open app
✓ Enter phone: +923334455667
✓ Tap Send OTP
✓ Receive SMS (real SMS, not demo)
✓ Enter 6-digit code
✓ Tap Verify
✓ Successfully logged in
✓ Check Firestore: users/{userId} exists
```

---

### TEST 2: Shop Setup with Logo
**Status:** ✅ READY

```
✓ On Shop Profile screen
✓ Tap logo circle
✓ Select image from gallery
✓ Logo preview appears
✓ Enter shop details:
  - Name: My Shop
  - Address: 123 Market St
  - Phone: 03334455667
  - Tax: NTN-12345
✓ Tap Finish Setup
✓ Navigate to Home screen
✓ Logo displays in PDF later
```

---

### TEST 3: Add Inventory
**Status:** ✅ READY

```
✓ Go to Inventory tab
✓ Add Product 1:
  Name: Tea
  Cost: 100
  Sell: 150
  Stock: 50
✓ Add Product 2:
  Name: Sugar
  Cost: 80
  Sell: 120
  Stock: 30
✓ Add Product 3:
  Name: Milk
  Cost: 60
  Sell: 90
  Stock: 20
✓ All products visible in list
✓ Verify SQLite database
```

---

### TEST 4: Create Bill (Offline)
**Status:** ✅ READY

```
Pre: Enable Airplane Mode

✓ Go to Billing tab
✓ Add Item → Search Tea
✓ Select Tea, Qty: 2
✓ Add Item → Search Sugar
✓ Select Sugar, Qty: 1
✓ Cart shows 2 items
✓ Subtotal: Rs. 420.00
✓ Tap Discount/Tax
✓ Set Discount: 20
✓ Set Tax %: 17
✓ Customer Name: Ahmed Khan
✓ Tap Apply
✓ Grand Total: Rs. 468.00
✓ Tap Checkout & Print
✓ PDF file created
✓ Share dialog appears
```

---

### TEST 5: PDF Invoice Quality
**Status:** ✅ READY

```
✓ Open PDF file
✓ Verify header:
  ✓ Shop logo (60x60px)
  ✓ Shop name: My Shop
  ✓ Address: 123 Market St
  ✓ Phone: 03334455667
  ✓ Tax: NTN-12345
✓ Verify invoice details:
  ✓ Invoice #: ABC12345
  ✓ Date: 28 Sep 2026, 03:16 PM
  ✓ Customer: Ahmed Khan
✓ Verify items table:
  ✓ Tea | 2 | Rs. 300.00
  ✓ Sugar | 1 | Rs. 120.00
✓ Verify calculations:
  ✓ Subtotal: Rs. 420.00
  ✓ Discount: -Rs. 20.00
  ✓ Tax (17%): Rs. 68.00
  ✓ Grand Total: Rs. 468.00 (bold)
✓ Footer: Thank you message
```

---

### TEST 6: Inventory Deducted
**Status:** ✅ READY

```
✓ Go to Inventory tab
✓ Tea stock: 50 - 2 = 48
✓ Sugar stock: 30 - 1 = 29
✓ Milk stock: 20 (unchanged)
✓ Open daily_sales table:
  ✓ Row 1: Tea, 100 cost, 150 sale
  ✓ Row 2: Sugar, 80 cost, 120 sale
```

---

### TEST 7: Multi-Device Sync
**Status:** ✅ READY (Requires 2 devices)

```
Device A (existing data):
✓ Disable Airplane Mode
✓ Internet ON
✓ Auto-sync to Firestore
✓ Check Firestore Console:
  ✓ users/{userId}/shop/profile
  ✓ users/{userId}/products (3 items)
  ✓ users/{userId}/bills (1 item)
  ✓ users/{userId}/sales (2 items)

Device B (fresh install):
✓ Launch app
✓ Login with same phone
✓ Receive OTP and verify
✓ Auto-load from Firestore
✓ Shop name: My Shop
✓ Logo displays correctly
✓ Products: 3 items visible
✓ Stock levels match Device A
```

---

### TEST 8: Offline to Online Sync
**Status:** ✅ READY

```
✓ Enable Airplane Mode
✓ Create 2nd bill (Milk: 1 × 90)
✓ Check local bills: 2 rows
✓ Check local sales: 3 rows
✓ Disable Airplane Mode
✓ Auto-sync triggered
✓ Firestore receives both bills
✓ Device B auto-syncs changes
✓ Both bills appear on Device B
```

---

### TEST 9: Financial Dashboard
**Status:** ✅ READY

```
✓ Go to Finance tab
✓ Today's Revenue: Rs. 936.00
✓ Today's Margin: Calculated
✓ Monthly Net Profit shown
✓ Add Expense:
  Label: Rent
  Amount: 10000
✓ Net Profit recalculated
```

---

### TEST 10: Supplier Management
**Status:** ✅ READY

```
✓ Go to Suppliers tab
✓ Add Supplier:
  Name: ABC Wholesale
  Phone: 03001234567
✓ Create Purchase Order:
  Tea: 50 units @ 100
  Sugar: 30 units @ 80
  Total: Rs. 7400
✓ Generate PO PDF
✓ PDF shows all details
✓ Share with supplier
```

---

## 🎯 Run Unit Tests

```bash
# All tests
flutter test

# Specific test
flutter test test/integration_test.dart -v
```

---

## 📋 Expected Results

| Test | Pass | Fail | Notes |
|------|------|------|-------|
| 1. Auth | ✅ | ❌ | Firebase Phone Auth |
| 2. Shop | ✅ | ❌ | Logo embedded in PDF |
| 3. Inventory | ✅ | ❌ | 3 products added |
| 4. Bill | ✅ | ❌ | Offline capability |
| 5. PDF | ✅ | ❌ | All details correct |
| 6. Stock | ✅ | ❌ | Deducted correctly |
| 7. Sync | ✅ | ❌ | Multi-device |
| 8. Offline→Online | ✅ | ❌ | Auto-sync |
| 9. Finance | ✅ | ❌ | Calculations correct |
| 10. Supplier | ✅ | ❌ | PO generation |

---

## 🐛 Troubleshooting

**Problem:** OTP not received
- Check phone has SMS enabled
- Verify phone format: +92XXXXXXXXXX
- Check Firebase Phone Auth enabled

**Problem:** Sync not working
- Verify internet connected
- Check firebase_options.dart credentials
- Check Firestore Security Rules
- Review: `flutter logs`

**Problem:** Logo not in PDF
- Verify logo file exists
- Check file permissions
- Try without logo first
- Check disk space

---

## ✅ Sign-off

All 10 tests passed? Deploy to production! 🎉
