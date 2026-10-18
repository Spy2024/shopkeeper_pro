# Remaining production workflow verification

This checklist is intentionally separate from unit-test results. Passing local SQLite tests does not prove Firebase security, live sync, device isolation, or phone usability.

## Live Firebase: two accounts / two devices

Use two separate Android devices (or one device plus a second device/emulator) and two distinct test Firebase users. Do not use production customer data.

- [ ] Sign in as Account A on Device A; create a uniquely named customer and product.
- [ ] Confirm those records sync to Account A's Firestore namespace.
- [ ] Sign in as Account B on Device B; verify Account A's records are not visible.
- [ ] Create a unique record as Account B; verify Account A cannot read it through app UI or direct Firestore access.
- [ ] Put Device A offline; create and edit a record; close/reopen app; reconnect; verify eventual sync.
- [ ] Verify failed writes remain queued and retry; verify updates/deletes and conflict policy.
- [ ] Log out and switch accounts on each device; verify cached local data is not exposed to the next user.
- [ ] Capture test date, app commit SHA, Firebase rules version, device/OS, and pass/fail evidence.

## Restaurant: order to kitchen to payment

- [ ] Create table and menu item; create order; add multiple items and notes.
- [ ] Verify saved total matches item quantity × price.
- [ ] Verify kitchen transitions queued → preparing → ready → served (or cancelled).
- [ ] Verify completion is blocked while kitchen items remain pending.
- [ ] Verify payment total must exactly match order total; mismatched and duplicate payments are rejected.
- [ ] Verify completion is blocked until fully paid and all kitchen items are served/cancelled.
- [ ] Verify successful completion releases the table and payment remains attached to the order.
- [ ] Verify after force-close/relaunch and on a physical Android phone.

## Vehicle and cargo

- [ ] Verify vehicle purchase cost, vendor/customer, sale proceeds, status and gross profit calculation.
- [ ] Verify expenses and cash/finance ledger reconcile; prevent duplicate sale.
- [ ] Verify cargo status history is append-only with time/location and invalid transitions are rejected.
- [ ] Verify customer-facing tracking reveals only a valid tracking token's allowed cargo fields, never internal account data.
- [ ] Verify reports reconcile with recorded transactions.

## Business-specific workflows

For each of school, clinic, salon, agriculture, construction and public services:

- [ ] Complete create → update → lifecycle/status change → payment/expense → report.
- [ ] Validate required fields, invalid amounts, duplicate identifiers and invalid state transitions.
- [ ] Verify user/branch isolation and sensitive-data access controls (especially clinic/patient records).
- [ ] Verify app restart persistence and offline/reconnect behavior where applicable.

## Web dashboard and hosting

- [ ] Configure a Firebase Web App using deployment/environment configuration; do not commit private credentials.
- [ ] Require Firebase authentication; deny access when signed out.
- [ ] Verify all queries are scoped to the authenticated UID and permitted branch.
- [ ] Verify Firestore rules enforce isolation independently of the UI.
- [ ] Build and deploy to Firebase Hosting (or approved HTTPS hosting); test refresh/deep links and mobile layout.
- [ ] Test account switching, expired session, unauthorized URL and empty/error/loading states.

## Release gate

- [ ] Flutter format, analyze, unit/widget tests and release build pass on the candidate SHA.
- [ ] Firebase Emulator tests cover Firestore rules and sync behavior.
- [ ] Real-device two-account test is recorded separately from emulator/local tests.
- [ ] Restaurant, vehicle/cargo and each business vertical have end-to-end evidence.
- [ ] Hosting URL, security rules, privacy policy, backups/restore and printing are checked before production claims.
