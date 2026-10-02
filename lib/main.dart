import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'providers/finance_provider.dart';
import 'providers/inventory_provider.dart';
import 'providers/pos_provider.dart';
import 'providers/sales_provider.dart';
import 'providers/shop_provider.dart';
import 'providers/supplier_provider.dart';
import 'providers/sync_provider.dart';
import 'screens/auth/phone_entry_screen.dart';
import 'screens/dashboard/home_screen.dart';
import 'screens/profile/shop_profile_screen.dart';
import 'utils/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
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
        home: const StartupGate(),
      ),
    );
  }
}

class StartupGate extends StatefulWidget {
  const StartupGate({super.key});

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final auth = context.read<AuthProvider>();
      await auth.checkExistingSession();

      if (auth.isLoggedIn) {
        await context.read<ShopProvider>().load();
        await context.read<InventoryProvider>().load();
        await context.read<SupplierProvider>().load();
        await context.read<SalesProvider>().load();
        await context.read<FinanceProvider>().load();

        if (auth.phoneNumber != null) {
          await context.read<SyncProvider>().init(auth.phoneNumber!);
        }
      }
    } catch (_) {
      // Keep startup resilient even if one provider fails to load.
    } finally {
      if (mounted) {
        setState(() => _ready = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final auth = context.watch<AuthProvider>();
    if (!auth.isLoggedIn) {
      return const PhoneEntryScreen();
    }

    final shop = context.watch<ShopProvider>().shop;
    if (shop == null) {
      return const ShopProfileScreen(isFirstSetup: true);
    }

    return const HomeScreen();
  }
}
