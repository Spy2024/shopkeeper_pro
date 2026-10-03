# Shopkeeper Pro

A production-ready shop management app blueprint for Flutter with offline-first local data, Firebase auth, Firestore sync, and invoice generation.

## Features
- Product management
- Customer records
- Billing and invoice generation
- Order history
- Inventory tracking
- Supplier management
- Daily sales summary
- Reports dashboard
- Offline-first local database
- Cloud sync-ready architecture

## Tech Stack
- Flutter
- Dart
- Firebase Authentication
- Firestore
- Firebase Storage
- SQLite (local cache)
- PDF & printing
- Share API

## Architecture
The app uses a layered architecture:
- UI screens
- Providers / state management
- Services (database, auth, sync, PDF)
- Firestore for cloud data
- SQLite for local offline caching

## Production Roadmap
1. Firebase Auth setup
2. Firestore schema implementation
3. Local sync queue design
4. Invoice branding/logo support
5. Reports and export features
6. Release build and deployment

## Project Structure

```text
lib/
  features/
    auth/
    shop/
    products/
    customers/
    billing/
    reports/
    sync/
  services/
    db_service.dart
    sync_service.dart
    pdf_service.dart
    auth_service.dart
```

## Notes
This project is designed as a production-ready foundation for a local retail business app, but it still requires Firebase setup and sync implementation to become fully cloud-synced and multi-device ready.

## Run
```bash
flutter pub get
flutter run
```

## GitHub
```bash
git init
git add .
git commit -m "Initial app"
git branch -M main
git remote add origin https://github.com/Spy2024/shopkeeper_pro.git
git push -u origin main
```
