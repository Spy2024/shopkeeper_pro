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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final options = DefaultFirebaseOptions.currentPlatform;
    final values = [options.apiKey, options.appId, options.projectId];
    final configured = values.every((v) =>
        v.isNotEmpty && !v.startsWith('YOUR_') && !v.contains('YOUR_'));
    if (configured) {
      await Firebase.initializeApp(options: options);
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

/// Decides where to land the user: login, shop-setup, or straight to the
/// dashboard, based on whatever's already saved on-device.
class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final auth = context.read<AuthProvider>();
    final shopProvider = context.read<ShopProvider>();
    final syncProvider = context.read<SyncProvider>();
    await auth.checkExistingSession();
    if (auth.isLoggedIn) {
      await shopProvider.load();
      final userId = auth.userUid;
      if (userId != null && userId.isNotEmpty) {
        await syncProvider.init(userId);
      }
    }
    if (!mounted) return;
    setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final auth = context.watch<AuthProvider>();
    if (!auth.isLoggedIn) return const PhoneEntryScreen();

    final shop = context.watch<ShopProvider>().shop;
    if (shop == null) return const ShopProfileScreen(isFirstSetup: true);

    return const HomeScreen();
  }
}
