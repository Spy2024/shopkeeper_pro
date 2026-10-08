# Shopkeeper Pro — Privacy Policy

**Status:** Draft for product-owner review. Replace the contact placeholder and have this policy reviewed for the jurisdictions where the app is distributed before publishing.

## Information the app may process
Shopkeeper Pro may store shop profile details, product and stock records, invoices, sales, expenses, supplier/customer details, and account identifiers. If Firebase Authentication and Firestore are configured, account and business data may be sent to the Firebase project configured by the shop owner. The app may also create PDF invoices or reports at the user's request.

## Local storage and synchronization
Business records are stored locally for offline operation. When cloud synchronization is enabled, records are synchronized to the signed-in user's cloud data path. Users should not share account credentials or exported statements with unauthorized people. Offline data can remain on the device until it is removed through supported app/account deletion procedures.

## Sharing and exports
PDFs shared through WhatsApp, email, or other Android sharing targets are transferred to the destination chosen by the user and are then subject to that destination's privacy practices. Review the recipient before sharing a statement or invoice.

## Security
The app is intended to restrict cloud records to the authenticated account. Security also depends on correct Firebase project configuration and deployed Firestore rules. Do not treat a build with placeholder Firebase settings or untested security rules as production-ready.

## Retention, deletion, and account recovery
Users should be given a way to export their records before requesting deletion. Account deletion must remove or appropriately retain cloud records according to applicable legal and accounting obligations; local records on each device must also be addressed. Account recovery must use the configured authentication provider and must not rely on a demo OTP.

## Children
Shopkeeper Pro is a business-management application and is not designed for children.

## Changes and contact
This policy may be updated as features change. Privacy questions and deletion requests: **[Add the shop owner's support email before publication]**.
