import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'providers/shop_provider.dart';
import 'providers/branch_provider.dart';
import 'providers/inventory_provider.dart';
import 'providers/pos_provider.dart';
import 'providers/supplier_provider.dart';
import 'providers/customer_provider.dart';
import 'providers/sales_provider.dart';
import 'providers/finance_provider.dart';
import 'providers/sync_provider.dart';
import 'screens/auth/phone_entry_screen.dart';
import 'screens/auth/legacy_database_migration_dialog.dart';
import 'services/db_service.dart';
import 'screens/profile/shop_profile_screen.dart';
import 'screens/dashboard/home_screen.dart';
import 'utils/theme.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final options = DefaultFirebaseOptions.currentPlatform;
    final values = [options.apiKey, options.appId, options.projectId];
    final configured = values.every((v) =>
        v.isNotEmpty && !v.startsWith('YOUR_') && !v.contains('YOUR_'));
    if (configured) {
      await Firebase.initializeApp(options: options);
      await FirebaseAppCheck.instance.activate(
        androidProvider: kReleaseMode ? AndroidProvider.playIntegrity : AndroidProvider.debug,
      );
    } else {
      debugPrint('[Firebase] Placeholder configuration detected; running offline mode.');
    }
  } catch (e) {
    debugPrint('[Firebase] Initialization skipped: $e');
  }
  runApp(const ShopkeeperProApp());
}

class ShopkeeperProApp extends StatelessWidget {
  const ShopkeeperProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ShopProvider()),
        ChangeNotifierProvider(create: (_) => BranchProvider()),
        ChangeNotifierProvider(create: (_) => InventoryProvider()),
        ChangeNotifierProvider(create: (_) => PosProvider()),
        ChangeNotifierProvider(create: (_) => SupplierProvider()),
        ChangeNotifierProvider(create: (_) => CustomerProvider()),
        ChangeNotifierProvider(create: (_) => SalesProvider()),
        ChangeNotifierProvider(create: (_) => FinanceProvider()),
        ChangeNotifierProvider(create: (_) => SyncProvider()),
      ],
      child: MaterialApp(
        title: 'Shopkeeper Pro',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        home: const _StartupGate(),
      ),
    );
  }
}

/// Decides where to land the user: login, shop-setup, or straight to the
/// dashboard, based on whatever's already saved on-device.
class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  bool _ready = false;
  String? _startupError;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (mounted) {
      setState(() {
        _ready = false;
        _startupError = null;
      });
    }

    try {
      final auth = context.read<AuthProvider>();
      final shopProvider = context.read<ShopProvider>();
      final syncProvider = context.read<SyncProvider>();

      await auth.checkExistingSession();
      if (auth.isLoggedIn) {
        await shopProvider.load();

        final userId = auth.userUid;
        if (userId != null && userId.isNotEmpty && auth.firebaseAvailable) {
          // Cloud sync is best-effort during startup. A network/rules error
          // must not prevent an otherwise usable offline POS from opening.
          try {
            await syncProvider.init(userId);
          } catch (error, stackTrace) {
            debugPrint('[Startup] Cloud sync initialization failed: $error');
            debugPrintStack(stackTrace: stackTrace);
          }
        }
      }
    } on LegacyDatabaseMigrationRequired {
      // Legacy data import must be an explicit ownership decision. Handle the
      // known migration state here rather than trapping the user on a retry
      // screen with no way to confirm the import.
      if (!mounted) return;
      try {
        final imported = await confirmLegacyDatabaseImport(context);
        if (!mounted) return;
        if (imported) {
          final auth = context.read<AuthProvider>();
          final shopProvider = context.read<ShopProvider>();
          await shopProvider.load();
          if (!mounted) return;
          final userId = auth.userUid;
          if (userId != null && userId.isNotEmpty && auth.firebaseAvailable) {
            try {
              await context.read<SyncProvider>().init(userId);
            } catch (error, stackTrace) {
              debugPrint('[Startup] Sync after legacy import failed: $error');
              debugPrintStack(stackTrace: stackTrace);
            }
          }
        } else if (mounted) {
          setState(() {
            _startupError =
                'Existing shop data needs ownership confirmation before it can be opened. Tap Retry to continue.';
          });
        }
      } catch (error, stackTrace) {
        debugPrint('[Startup] Legacy database import failed: $error');
        debugPrintStack(stackTrace: stackTrace);
        if (mounted) {
          setState(() {
            _startupError =
                'The existing shop data could not be imported. Please retry or contact support.';
          });
        }
      }
    } catch (error, stackTrace) {
      // Never leave the launch screen spinning forever when local database
      // migration/opening or session restoration fails.
      debugPrint('[Startup] App initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _startupError =
              'Shopkeeper Pro could not finish starting. Please retry. If this keeps happening, share the error details with support.';
        });
      }
    } finally {
      if (mounted) setState(() => _ready = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final startupError = _startupError;
    if (startupError != null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.storefront_rounded,
                      size: 64,
                      color: AppTheme.ink,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Shopkeeper Pro could not start',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    Text(startupError, textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _bootstrap,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final auth = context.watch<AuthProvider>();
    if (!auth.isLoggedIn) return const PhoneEntryScreen();

    final shop = context.watch<ShopProvider>().shop;
    if (shop == null) return const ShopProfileScreen(isFirstSetup: true);

    return const HomeScreen();
  }
}
