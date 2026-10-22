import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'screens/dashboard/web_dashboard_screen.dart';
import 'utils/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var ready = false;
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
    ready = true;
  } catch (error) {
    debugPrint('Firebase web initialization failed: $error');
  }
  runApp(_ShopkeeperWebApp(firebaseReady: ready));
}

class _ShopkeeperWebApp extends StatelessWidget {
  const _ShopkeeperWebApp({required this.firebaseReady});
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
      : const Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Firebase web configuration is missing or invalid. Build with FIREBASE_WEB_* and FIREBASE_PROJECT_ID dart-defines. See docs/firebase-web-dashboard-and-live-tests.md.'),
            ),
          ),
        ),
  );
}
