import 'dart:async';
import 'package:flutter/foundation.dart';
import 'screens/dashboard/web_dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'providers/shop_provider.dart';
import 'providers/inventory_provider.dart';
import 'providers/pos_provider.dart';
import 'providers/supplier_provider.dart';
import 'providers/sales_provider.dart';
import 'providers/finance_provider.dart';
import 'providers/sync_provider.dart';
import 'screens/auth/phone_entry_screen.dart';
import 'screens/profile/shop_profile_screen.dart';
import 'screens/dashboard/home_screen.dart';
import 'utils/theme.dart';
import 'package:firebase_core/firebase_core.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var firebaseReady = false;

  // Firebase is optional until real project credentials are configured.
  // Keep the offline-first app usable instead of blocking startup.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    firebaseReady = true;
  } catch (e) {
    debugPrint('Firebase initialization skipped: $e');
  }

  runApp(kIsWeb ? ShopkeeperProWebApp(firebaseReady: firebaseReady) : const ShopkeeperProApp());
}

class ShopkeeperProWebApp extends StatelessWidget {
  const ShopkeeperProWebApp({super.key, required this.firebaseReady});
  final bool firebaseReady;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Shopkeeper Pro Web Dashboard',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: ThemeMode.system,
    home: firebaseReady
        ? const WebDashboardScreen()
        : const Scaffold(body: Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Firebase web configuration is missing or invalid. Build with the FIREBASE_WEB_* and FIREBASE_PROJECT_ID dart-defines described in docs/firebase-web-dashboard-and-live-tests.md.')))),
  );
}

class ShopkeeperProApp extends StatelessWidget {
  const ShopkeeperProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ShopProvider()),
        ChangeNotifierProvider(create: (_) => InventoryProvider()),
        ChangeNotifierProvider(create: (_) => PosProvider()),
        ChangeNotifierProvider(create: (_) => SupplierProvider()),
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

class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  bool _ready = false;
  String? _initializedUserId;
  String? _initializingUserId;
  AuthProvider? _authProvider;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final auth = context.read<AuthProvider>();
    await auth.checkExistingSession();
    if (!mounted) return;
    _authProvider = auth;
    auth.addListener(_onAuthChanged);
    if (auth.isLoggedIn && auth.userUid != null) {
      await _initializeAccountServices(auth.userUid!);
    }
    if (mounted) setState(() => _ready = true);
  }

  void _onAuthChanged() {
    final auth = _authProvider;
    if (auth == null) return;
    if (!auth.isLoggedIn) {
      _initializedUserId = null;
      return;
    }
    final uid = auth.userUid;
    if (uid != null && uid != _initializedUserId) {
      unawaited(_initializeAccountServices(uid));
    }
  }

  Future<void> _initializeAccountServices(String userId) async {
    if (_initializedUserId == userId || _initializingUserId == userId) return;
    _initializingUserId = userId;
    try {
      await context.read<SyncProvider>().init(userId);
      // Sync/pull first so cloud-restored rows are reflected in provider state.
      await context.read<ShopProvider>().load();
      await context.read<InventoryProvider>().load();
      await context.read<PosProvider>().loadHistory();
      await context.read<SupplierProvider>().load();
      await context.read<SalesProvider>().load();
      await context.read<FinanceProvider>().load();
      _initializedUserId = userId;
    } catch (error, stackTrace) {
      debugPrint('[StartupGate] Account initialization failed: $error\\n$stackTrace');
    } finally {
      _initializingUserId = null;
      if (mounted) setState(() => _ready = true);
    }
  }

  @override
  void dispose() {
    _authProvider?.removeListener(_onAuthChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final auth = context.watch<AuthProvider>();
    if (!auth.isLoggedIn) return const PhoneEntryScreen();

    if (kIsWeb) return const WebDashboardScreen();

    final shop = context.watch<ShopProvider>().shop;
    if (shop == null) {
      return const ShopProfileScreen(isFirstSetup: true);
    }

    return const HomeScreen();
  }
}
