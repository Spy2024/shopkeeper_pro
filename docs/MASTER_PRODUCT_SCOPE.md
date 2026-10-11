# Shopkeeper Pro — Master Product Scope and Acceptance Checklist

**Purpose:** One configurable business-management product, not a retail-only billing app. Target platforms: Android app and web dashboard. Existing PR #10 is the stabilization base. Keep this PR in draft until all release gates pass.

**Status rule:** A requirement marked Planned or In progress is not implemented merely because it appears in this document or in the business-type catalog. Mark Done only after code, automated tests, and the applicable live/device verification are complete.

## 1. Product foundations

- [ ] Business onboarding wizard: business type, legal/display name, address, phone, email, tax registration, currency, timezone, logo, invoice numbering, tax defaults, opening cash/stock, fiscal year, language, first branch, owner account.
- [x] Business-type selector and persistent business type on shop profile (initial foundation).
- [ ] Selectable module enable/disable controls with module dependencies and per-business defaults.
- [ ] Business types: general retail/general store, supermarket, wholesale/distribution, clothing/garments, shoes/footwear, mobile/electronics, pharmacy/medical store, cosmetics, hardware/building materials, restaurant/cafe, car showroom/dealership, motorcycle showroom, vehicle workshop/service center, trucking/fleet, passenger transport, goods/cargo transport, rent-a-car, public service office, private services/agency, repair/maintenance, salon/spa, school/academy, clinic/healthcare, agriculture/farm supplies, construction/contractor, and other/custom.
- [ ] Common platform behavior: offline-first where practical, clear sync state, conflict handling, audit history, data export, accessibility, responsive layouts, localization, and safe upgrades.
- [ ] Role and entitlement checks must be enforced in providers/services and backend rules, not only by hiding UI.

## 2. Core POS and sales

- [ ] Product search, barcode scan, category/filter, cart, quantity/units, price overrides with permission, line and bill discounts, tax, rounding rules, notes, customer selection.
- [ ] Payment methods: cash, bank transfer, card, wallet/digital payment, cheque, credit/udhaar, mixed tender, partial payment, advance/deposit, change due, payment reference and settlement status.
- [ ] Atomic checkout: validate stock/prices, save bill and lines, save payments, deduct stock, record sales/COGS, update customer balance, append audit event, enqueue sync; rollback all local writes on failure.
- [ ] Invoice/receipt numbering, configurable invoice template, tax IDs, shop/branch details, thermal and A4 PDF, print, reprint, share to WhatsApp/Gmail/system share sheet.
- [ ] Sales returns/exchanges, partial item returns, refund to original or selected payment method, exchange price difference, restock/damaged-stock decision, return reason, duplicate-return prevention.
- [ ] Void/cancel bill with authorization and audit trail; never silently delete a posted financial transaction.
- [ ] Sales history filters by date, cashier, branch, customer, payment type, status and invoice number.

## 3. Products and inventory

- [ ] Fields: product ID/SKU, name, alternate/search name, description, category, brand, unit, barcode(s), supplier, purchase cost, sale price, wholesale price, minimum sale price, tax code/rate, current quantity, reorder/low-stock level, warehouse/bin, batch/lot, manufacturing date, expiry date, serial/IMEI, warranty, image, active/archive state, created/updated timestamps.
- [ ] Variants: size, color, model, pack size and variant-specific SKU/barcode/pricing/stock.
- [ ] Stock ledger: opening stock, purchases, sales, returns, transfers, damage, expiry/write-off, manual adjustments, physical counts and reconciliation.
- [ ] Multiple units and conversions (piece/box/carton/kg/litre/metre), fractional quantity where the business allows it.
- [ ] Low-stock and expiry alerts; batch selection/FEFO where relevant; expired-item sale block configurable only for businesses where appropriate.
- [ ] Costing strategy configured and documented (moving average/FIFO where required); never present estimates as audited profit.
- [ ] Import/export CSV/Excel with preview, validation, duplicate detection and rollback-safe import.
- [ ] Inventory valuation, stock aging, fast/slow-moving, dead stock, gross margin and shrinkage reports.

## 4. Purchases, suppliers and procurement

- [ ] Supplier fields: ID, business/person name, phone, email, address, tax number, opening balance, credit terms, contact person, bank/payment details, status and notes.
- [ ] Purchase order, approval, goods receipt, supplier invoice, item lines, quantities, unit conversions, batch/expiry/serials, freight/other costs, tax, discounts and attachments.
- [ ] Receiving stock updates only after goods receipt; purchase returns reverse stock and payable correctly.
- [ ] Supplier ledger: invoices, payments, partial settlements, debit/credit notes, opening balance, current payable, due dates, aging and statement PDF.
- [ ] Reorder suggestions, preferred suppliers, purchase history and purchase-price comparison.

## 5. Customers, receivables and udhaar

- [ ] Customer fields: ID, name, phone, email, address, tax ID, opening balance, credit limit, payment terms, due date, notes and status.
- [ ] Customer ledger: opening balance, credit sales, receipts, partial payments, refunds, adjustments, running balance, invoice references and audit history.
- [ ] Credit approval and limit warnings; never allow balance to be silently overwritten.
- [ ] Receipts with payment method/reference, allocation to one or more invoices, remaining balance, receipt print/share and reversal workflow.
- [ ] Due reminders with configurable consent, schedule and delivery channel; record sent/failed status.
- [ ] Customer statement PDF, aging report, purchase history and outstanding balance report.

## 6. Finance and accounting

- [ ] Accounts chart, cash/bank/wallet accounts, opening balances and controlled journal entries.
- [ ] Cashbook and daily cash closing: opening cash, cash sales, collections, supplier payments, expenses, refunds, deposits/withdrawals, expected cash, counted cash and variance.
- [ ] Income/expense categories, recurring expenses, attachments, approvals and payment account.
- [ ] Proper ledger treatment for sales, COGS, stock, purchases, returns, tax, receivables, payables, payments and refunds.
- [ ] Reports: daily/weekly/monthly/custom-range sales, purchases, collections, payments, expenses, gross profit, net profit/loss, cash flow, balance sheet, trial balance, receivables/payables aging, tax summary and branch comparison.
- [ ] Explicitly distinguish cash received from sales revenue, gross profit from net profit, and estimates from ledger-reconciled results.
- [ ] Export/print/share financial statements in PDF and CSV/Excel with date range, filters, currency, generation time and page numbering.

## 7. Multi-branch, warehouses and staff

- [ ] Branch fields: ID, name, unique code, address, phone, manager, opening date, active state, timezone, invoice prefix and settings.
- [ ] Multiple warehouses/stock locations; branch-level inventory, price lists, cash accounts, expenses, sales, purchases and reports.
- [ ] Stock transfer request, approval, dispatch, in-transit, receive/shortage/damage reconciliation and immutable transfer ledger.
- [ ] Consolidated owner dashboard and branch-specific reports; branch isolation tests and permissions.
- [ ] Staff fields: ID, name, phone/email, branch assignments, role, active status, invite/login state and last access.
- [ ] Roles: owner, admin, manager, cashier, accountant, inventory clerk, purchasing officer, driver, technician and custom roles.
- [ ] Permission matrix by module/action (view/create/edit/approve/void/export/manage users); enforce server-side where cloud data is involved.
- [ ] Shift open/close, cashier reconciliation, activity log, device/session management and staff offboarding.

## 8. Business-specific modules

### 8.1 Trucking and fleet
- [ ] Vehicle fields: registration, make/model/year, type, capacity, ownership/lease, documents/expiry, insurance, fitness/permit, tracker ID, odometer, fuel type and active state.
- [ ] Driver fields: identity/contact, licence class/number/expiry, emergency contact, employment/commission, assigned vehicle and status.
- [ ] Trips/jobs: trip ID, customer, pickup/drop-off, route, cargo, weight/volume, dates, vehicle, driver/helper, rate, advances, balance, status, proof of delivery and attachments.
- [ ] Fuel logs: date, odometer, litres, price, vendor, vehicle, receipt and mileage efficiency.
- [ ] Maintenance/repairs, tyres, parts, scheduled service, breakdowns, downtime and costs.
- [ ] Freight invoices, customer receivables, driver advances/settlement, tolls, permits, commissions and trip-level profitability.
- [ ] Fleet utilization, cost/km, revenue/km, on-time delivery and vehicle profitability reports.

### 8.2 Passenger transport
- [ ] Routes, stops, timetables, fares, seat capacity, bookings, tickets, cancellations/refunds, passenger manifests and route revenue.
- [ ] Vehicle/driver assignment, attendance/shift, fuel, maintenance, permits and service alerts.

### 8.3 Goods/cargo transport
- [ ] Consignment/booking number, sender/receiver, addresses, packages, weight/dimensions, declared value, freight, COD, tracking events, delivery proof, shortage/damage and claims.
- [ ] Waybill, delivery challan, customer billing, carrier/driver settlement and consignment status history.

### 8.4 Car/motorcycle showroom
- [ ] Vehicle inventory: VIN/chassis, engine number, make/model/variant, model year, color, mileage, purchase source/cost, advertised/sale price, registration status and document scans.
- [ ] Vehicle acquisition, inspection, stock status, reservation/deposit, sale agreement, trade-in, financing/instalments, delivery checklist and ownership-transfer documents.
- [ ] Customer KYC fields only when legally necessary, protected by role access and retention policy.
- [ ] Commission, deal costs, warranty/service history, vehicle margin and showroom stock reports.

### 8.5 Workshop/service center/repair
- [ ] Job card: customer, vehicle/device, serial/IMEI, reported issue, inspection, estimate, approval, assigned technician, labour, parts, status, promised date and sign-off.
- [ ] Service catalogue, labour rates, parts consumption, warranty jobs, subcontracting, customer updates, final invoice and service history.
- [ ] Appointment calendar, technician workload, turnaround time and job profitability.

### 8.6 Public/private service office and other services
- [ ] Service catalogue, request/case number, applicant/customer, required documents, appointments/queue, assigned staff, status, fee/quote, receipts, SLA/deadline, notes and audit history.
- [ ] Public-sector deployments must not imply government affiliation; configure legal notices, data minimization, access control and retention requirements.
- [ ] Agency/project work: proposals, milestones, timesheets, deliverables, invoices, deposits, expenses and project profitability.

### 8.7 Other verticals
- [ ] Restaurant: menu/recipes, tables, kitchen orders, modifiers, wastage, ingredient stock and delivery.
- [ ] Clothing/shoes: size/color variants, exchange workflow and seasonal stock.
- [ ] Pharmacy: batches, expiry, supplier traceability and jurisdiction-specific safeguards.
- [ ] Electronics: serial/IMEI, warranty and repair history.
- [ ] School/academy: students, guardians, admissions, class/section, attendance, fee plans, receipts, arrears and privacy controls.
- [ ] Clinic: appointments, service billing and restricted patient data; clinical records require a separate compliance review before implementation.
- [ ] Agriculture: inputs, crop/field, harvest lots, seasonal costs and sales.
- [ ] Construction: projects, estimates, BOQ/materials, subcontractors, workers, milestones, retention and project cash flow.

## 9. Account, security, sync and backups

- [ ] Phone OTP and email/password sign-in, email verification, password reset, secure account linking and recovery.
- [ ] Per-user/per-business/per-branch data isolation, least-privilege Firestore/Storage rules and automated security tests.
- [ ] Offline queue with idempotent operations, retry/backoff, conflict policy, delete tombstones, sync status and recovery from interrupted sync.
- [ ] Manual local backup, manual cloud backup, scheduled cloud backup, encrypted sensitive backup where feasible, retention/versioning and last-success status.
- [ ] Restore preview, backup format/version validation, ownership validation, transaction-safe restore, rollback on failure and post-restore reconciliation.
- [ ] Account export/deletion and backend callable deployment checks; document retention/deletion behavior for local, cloud, storage and backups.
- [ ] Never put service account credentials or private secrets in the client repository.

## 10. Android and web dashboard

- [ ] Android: responsive screens, camera/barcode permissions, printing/share, background sync constraints, app lifecycle, migrations and offline behavior.
- [ ] Web: responsive owner/admin dashboard, secure Firebase auth, branch/module permission checks, reports, filters, exports and online sync status.
- [ ] Use a deliberate cross-platform data-access layer: SQLite only on supported mobile platforms and an appropriate web persistence/cache strategy; do not pretend mobile sqflite works in browsers.
- [ ] Test small phones, tablets and desktop widths; keyboard navigation and accessible labels for web.

## 11. Language, reminders, onboarding and support

- [ ] Urdu and English localization, RTL layouts for Urdu, date/number/currency formats and translated validation/error text.
- [ ] Alerts: low stock, expiry, overdue customer invoices, overdue supplier invoices, vehicle document expiry, service due, maintenance, backups failing and sync failures.
- [ ] Notification consent, quiet hours, retry, in-app notification center and delivery log.
- [ ] Guided onboarding, sample/demo data clearly labelled, import wizard, help/FAQ, searchable user guide, feedback form and support contact.
- [ ] Free/Pro subscription plan is a proposal until pricing, limits, billing provider, restore purchases, grace periods and entitlement enforcement are explicitly decided and implemented.

## 12. Quality and release gates

- [ ] Unit tests for models/calculations/validation and provider tests for each critical workflow.
- [ ] Database migration tests from every supported prior schema; backup compatibility and restore rollback tests.
- [ ] Integration tests: checkout, returns, payments, udhaar, purchase receiving, stock transfers, finance, account switch, offline sync and conflict recovery.
- [ ] Firebase emulator/live test plan for Auth, Firestore, Storage and callable functions; verify rules with unauthorized and cross-user requests.
- [ ] Physical Android test: fresh install, upgrade existing data, OTP/email login, camera scanner, checkout, printer/share, offline/reconnect, backup/restore.
- [ ] Web browser tests, responsive/accessibility checks and web storage validation.
- [ ] CI dependency resolution, formatter, analyzer, tests, web build, Android debug build and opt-in signed release build.
- [ ] Production signing, crash reporting, privacy policy, support path, backups, monitoring and rollback plan.
- [ ] Release is blocked if any critical test is failing or any feature is claimed verified without evidence.

## 13. Delivery order

1. Stabilize and test existing checkout, inventory, returns, backup/restore and sync.
2. Complete payments, customer receivables/udhaar, supplier payables and accounting.
3. Implement branches, warehouses, transfers, staff roles and audit logs.
4. Implement vertical modules in prioritized slices: trucking/fleet, vehicle showroom, passenger/goods transport, public/private service office, then other verticals.
5. Build web dashboard and cross-platform data layer.
6. Add localization, reminders, onboarding, help/feedback and subscription entitlement support if approved.
7. Complete live/device/security verification, signed release and release checklist.

## Current implementation notes

- Business type selection is being added to shop setup/profile; the list of default modules is a configuration catalog, not yet a promise that each vertical's workflows are functional.
- A local branches table is a schema foundation only; branch CRUD, transfer ledger, permissions, cloud sync and consolidated reports remain pending.
- CI passing proves only the automated checks included in that run. It does not prove production Firebase, printer, device, web or release readiness.
