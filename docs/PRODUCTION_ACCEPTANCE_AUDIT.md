# Shopkeeper Pro — Professional Acceptance Audit

Audit date: 2026-10-20
Repository: https://github.com/Spy2024/shopkeeper_pro
Audited candidate: `feature/phase1-6-verified-completion`
Candidate HEAD observed before this report: `a80acb614191de17e551c40a9989203b78a657d0`
Status: **IN PROGRESS — NOT PRODUCTION READY**

This is an evidence-based gate list, not a claim that the listed work is complete. A passing CI run proves only the jobs it actually ran; it does not prove real-device behaviour, live Firebase configuration, complete business workflows, visual parity, or pilot acceptance.

## Evidence observed

- Default branch `main` currently points to `d2d2367063200e97f0da5e6e21fb5aa4686642ef`; it is older than the active feature candidate.
- Several substantial pull requests are open and marked draft: #18, #17, #15, #14, #13, #12, #11, #7, #6, and #2. PR #18 is based on PR #12's feature branch; other work is also stacked across feature branches. Do not merge blindly or assume one PR contains every change.
- On candidate SHA `a80acb614191de17e551c40a9989203b78a657d0`, Flutter CI run #186 completed successfully, including dependency resolution, `flutter analyze`, `flutter test`, debug APK build, and debug APK artifact upload.
- Firebase Rules CI run #51 completed successfully on the same candidate SHA.
- Build Release APK run #500 failed at **Prepare release signing**; the release build and artifact upload were skipped. A signed release APK is therefore **not verified**. Confirm signing secrets/configuration in GitHub Actions without exposing their values.
- PR #18 description explicitly lists physical-phone launch/crash verification, live Firebase two-account/two-device isolation, backup/restore round-trip, hardware printing/scanner checks, every-screen visual comparison, and full business-category workflows as still unverified.
- Brand guide file `Shopkeeper_Pro_Theme_Logo_Brand_Guide.pdf` was inspected. It requires Navy `#0B3D91`, Teal `#14B8A6`, Gold `#FFBF24`, Light Gray `#F3F4F6`, Dark Navy `#082B4C`; shopping-cart + rising-chart logo; rounded navy app icon with teal growth arrow and gold cart; light/dark themes; readable typography; branded color A4 invoice; and separate black-and-white thermal receipt considerations.
- Candidate code contains matching theme tokens and a cart/chart brand mark; PDF service contains the branded A4 invoice palette. This establishes partial code integration only, not screen-by-screen visual parity or on-device verification.
- Candidate Android manifest names `com.example.shopkeeper_pro.MainActivity`, and the Kotlin activity is in that package. A previously supplied older crash log referenced `com.shopkeeperpro.app.MainActivity`; this is evidence about that installed APK/version, not proof that the current candidate still has the same manifest problem. Current candidate must still be installed and launch-tested.
- Firestore rules include UID scoping and a default-deny fallback. The allowlist has repeated collection names; duplicates are not by themselves a permission bypass, but the allowlist must be reconciled against all sync mappings and tested with the emulator and live Firebase.
- SQLite database service uses per-user database names, explicit legacy ownership confirmation, and schema version 22 in the candidate. Migration, restart persistence, account switching, backup/restore, and all new vertical records still require regression and device acceptance.

## Current gate status

| Gate | Status | Evidence / remaining work |
|---|---|---|
| Requirements and business workflow inventory | In progress | Consolidate requirements for every category, role, screen, and report. |
| PDF branding/design system | Partially implemented | Theme tokens, brand mark and invoice colors exist; audit every screen, launcher icon size, PDF layout, dark theme and real-device appearance. |
| Architecture and database | Partially implemented | Inspect all migrations, foreign-key/transaction boundaries, deletion/tombstones, child records and account switching. |
| Core POS and stock | Automated tests pass on candidate CI | Must verify checkout, payments, stock ledger and bill history after app restart on Android hardware. |
| Customer credit, split payments, returns/refunds | Tests/features present in draft branches | Verify accounting reconciliation and end-to-end device workflows; do not infer completeness from screen presence. |
| Specialized business modules | Incomplete / not accepted | Restaurant, vehicle, cargo, school, clinic, salon, agriculture, construction, public services, clothing, cosmetics and spare parts need workflow-by-workflow acceptance. |
| Offline/cloud sync | Partially implemented | Verify every table and child record, retry, conflict policy, deletion tombstones, duplicate prevention and account isolation. |
| Firebase production setup | Not verified | Confirm real Android/Web app configuration, deployed rules, App Check, Auth providers, Hosting and Cloud Function deployment. Never commit credentials or share secret values. |
| Backup and restore | Not verified end-to-end | Run backup → destructive-safe restore → record counts/reconciliation → sync retry tests using test data. |
| CI / analyzer / tests / debug APK | Passed on candidate SHA | Flutter CI #186 succeeded; Firebase Rules CI #51 succeeded. Re-run after each change. |
| Signed release APK | Blocked / not verified | Build Release APK run #500 failed before build at release signing preparation. Configure secrets securely, then rerun. |
| Physical install, launch and upgrade | Not verified | Preserve existing local data; test fresh install and upgrade separately and capture Logcat for any launch failure. |
| Pilot shop acceptance | Not started / not evidenced | Require 2–5 pilot shops and signed-off scenario results before production claim. |

## Required acceptance tests

### Product and UX
- [ ] Compare every screen against the brand guide, not just dashboard and billing.
- [ ] Verify all navigation items and buttons lead to working actions.
- [ ] Verify loading, empty, error, success and confirmation states.
- [ ] Verify light/dark theme, text contrast, small-screen layout and localization.
- [ ] Verify branded A4 invoice, shop/customer details, totals, page breaks and share/save.
- [ ] Verify thermal receipt separately for supported 58/80 mm printers.

### Core business integrity
- [ ] Create product, close/reopen app, confirm product persists.
- [ ] Create sale with cash, split payment and credit; reconcile bill, payment ledger, daily sales, cash and stock.
- [ ] Close/reopen app and confirm bill history and bill items persist.
- [ ] Attempt insufficient-stock checkout and verify no partial write.
- [ ] Return against original bill, restore correct stock, reverse correct payment/credit and reject duplicate return.
- [ ] Verify branch transfer conserves stock and records both sides.
- [ ] Verify reports reconcile to source transactions and expenses.

### Identity, security and sync
- [ ] Test two separate Firebase users on two devices; no cross-account local or cloud data exposure.
- [ ] Test sign-out/account switch, reconnect, retry, conflicting edits, delete propagation and duplicate prevention.
- [ ] Test rules for unauthenticated access, own UID, other UID, unknown collection and child-document paths.
- [ ] Verify App Check and production authentication flows against the intended Firebase project.
- [ ] Test backup/restore and restore reconciliation without deleting production data.

### Release and operations
- [ ] Run analyzer, automated tests, Firestore rules tests and debug build on the exact release candidate.
- [ ] Configure and validate Android release signing securely; never log secret values.
- [ ] Verify signed artifact installation, first launch, restart and upgrade without uninstalling the user's existing data first.
- [ ] Complete pilot acceptance for representative shop types and document any known limitations.

## Release decision

**Do not merge stacked draft PRs or declare production-ready until the exact candidate is reviewed, CI is green, release signing/build is successful, and all required device/Firebase/pilot acceptance tests are evidenced.**