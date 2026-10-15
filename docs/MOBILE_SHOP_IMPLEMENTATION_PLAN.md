# Shopkeeper Pro — Mobile Shop Implementation Plan

**Status: Planned / implementation in progress.** This document defines the target workflow; it is not evidence that these features already work in the app.

## Goal

Make `mobile_electronics` the first fully validated business category. Reuse the existing Shopkeeper Pro POS, inventory, purchase, customer, supplier, payment, returns, reports, backup and sync foundation wherever the audit confirms it is safe. Add mobile-specific fields and workflows without breaking existing general-retail shops.

## Setup experience

After account login:
1. Create or select a shop.
2. Choose **Mobile Shop / Electronics** as the primary business type.
3. Review module choices: New Mobiles, Used Mobiles, Accessories, Spare Parts, Repair Jobs, Software Services and Warranty.
4. Configure shop/receipt details, opening stock, suppliers, customers and optional branches.
5. Show a mobile-shop dashboard with relevant actions; retain common POS, Hisaab, expenses, reports, backup and settings.

The current profile selector persists a business type, but a guided module-selection wizard and category-specific dashboard are separate work items.

## Inventory catalog

### A. New mobile devices
- Brand, model, variant, RAM, storage, colour, network/SIM variant and condition.
- Unique IMEI 1 / IMEI 2 or serial number per physical unit.
- Supplier, purchase invoice/date, unit cost, sale price, discount floor/approval, tax, warranty duration and warranty terms.
- Status: ordered, received, in stock, reserved, sold, returned, repair/inspection, written off.
- Duplicate IMEI/serial detection and a unit-history timeline.

### B. Used mobile intake and resale
- Seller identity/contact fields limited to business need; purchase date, price, receipt/reference and staff member.
- Brand/model, IMEI, colour/storage, cosmetic condition grade, screen/touch, cameras, speaker/mic, charging, buttons, network/SIM and battery/health checklist.
- Included accessories, known defects, inspection notes, optional condition photos and customer acknowledgement.
- Status: inspection pending, repair required, ready for sale, reserved, sold, returned or rejected.
- Purchase cost + linked repair/parts cost + other approved acquisition costs should feed the chosen costing method; show margin only when the underlying costs are known.

### C. Accessories
- Covers/cases, screen protectors, tempered glass, chargers/adapters, USB/lightning/type-C cables, handsfree/earbuds, power banks, holders, memory cards, OTG adapters, SIM accessories and other custom accessories.
- Brand, compatible device/model, colour, connector/specification, pack/unit, barcode, cost, sale price, reorder level and supplier.

### D. Mobile parts
- LCD/display panel, touch glass, charging jack/port, charging base/sub-board, battery, main/charging flex, power/volume flex, speaker/earpiece, microphone, camera modules, back cover, frame, buttons, SIM tray, connectors, motherboard, ICs and other custom parts.
- Part number/SKU, brand/quality grade, compatible phone models, supplier, bin/location, cost, price, quantity, warranty and defective/return status.
- Compatibility is searchable and must not be falsely assumed; allow authorised override with reason where fitment data is incomplete.

## Repair and software service jobs

### Repair job card
- Unique job number; customer and contact; device type/model/IMEI/serial; reported problem; received condition and accessories.
- Diagnosis, estimate, customer approval, promised date, assigned technician and job status.
- Labour fee, parts consumed, discount/tax, advance, balance, repair warranty, quality check and delivery confirmation.
- Suggested states: received → inspection → estimate sent → awaiting approval → in progress → waiting for parts → quality check → ready → delivered; include cancelled/rejected with reason.

### Software services
- Service catalogue for authorised OS/software updates, lawful flashing/reinstall, data transfer, backup/restore and setup assistance.
- Record customer consent, requested work, quoted fee, technician, completion status and receipt.
- Do not store customer passwords or private data unless strictly necessary and specifically authorised; prefer not to collect them at all. Only support lawful, customer-authorised servicing.

## POS, payments and customer records
- Sell a serialized device by selecting its exact IMEI/serial unit, not merely decrementing a generic quantity.
- Support accessories/parts in the same cart, line/bill discounts with permissions, tax, cash/card/bank/wallet/credit and split tender if supported by verified core.
- Link the bill to the customer when provided; issue receipt/PDF and support print/reprint/share only after device verification.
- Return/exchange must reference the original bill and unit; prevent duplicate returns and decide restock, inspection or damaged status.
- Credit sales and collections should flow to the customer ledger; profit reports must distinguish revenue, cost, refunds and expenses.

## Suggested screens
1. Mobile Shop Dashboard
2. Device Inventory (New / Used / Reserved / Sold)
3. Add New Device
4. Buy Used Device / Inspection
5. Accessories & Parts Catalog
6. Repair Jobs List
7. Repair Job Card / Estimate
8. Software Service Entry
9. IMEI / Serial Search and History
10. Warranty / Returns
11. Supplier Purchase and Receiving
12. Mobile Sales / POS
13. Customer History and Hisaab
14. Mobile-specific reports and export

## Required tests before calling it complete
- Existing general-retail shop still opens with no migration/data loss.
- Mobile category is saved/reloaded and defaults are stable; cosmetics remains selectable.
- Duplicate IMEI/serial is blocked or handled by a documented authorised flow.
- New-device sale marks the exact unit sold and return restores the correct state.
- Used-device intake records inspection and costs; repair costs are linked to the correct device.
- Repair job estimate, approval, parts consumption, labour, payment and delivery reconcile.
- Software job requires recorded service consent; no sensitive credentials are stored by default.
- Offline sale/reconnect does not duplicate bill, stock movement or sync operation.
- Account switching cannot expose another shop's devices, IMEIs, customers or jobs.
- Backup/restore round-trip preserves device units, jobs, parts usage, bills and ledger links.
- CI analyzer, automated tests and Android debug build pass; physical printer/scanner and Firebase checks are separately recorded.

## Implementation order
1. Add category defaults and tests (current branch).
2. Inspect existing product schema, migrations, POS provider and sync payload before choosing a schema extension.
3. Design backward-compatible serialized-device and repair-job data model with migration tests.
4. Implement repository/service layer and unit tests before UI.
5. Add screens and connect them to the existing shop/account scope.
6. Add sync/backup/restore coverage and integration tests.
7. Review CI and only then arrange controlled device testing.

## Release honesty
A category entry or module identifier is a configuration hint, not an implemented feature. Mark an item complete only after code, automated tests and applicable live/device verification are documented.
