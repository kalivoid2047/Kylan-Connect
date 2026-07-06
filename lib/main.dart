import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/themes/app_theme.dart';
import 'routes/app_router.dart';
import 'providers/settings_provider.dart';
import 'services/app_startup_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    // Kylan Connect relies on raw UDP/TCP sockets which are not available on
    // the web platform. Run the app in a degraded state that shows a clear
    // message rather than crashing silently.
    runApp(const _WebUnsupportedApp());
    return;
  }

  await AppStartupService.instance.initialize();

  runApp(
    const ProviderScope(
      child: KylanConnectApp(),
    ),
  );
}

class _WebUnsupportedApp extends StatelessWidget {
  const _WebUnsupportedApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Kylan Connect',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.wifi_off, size: 80, color: Colors.grey),
                SizedBox(height: 24),
                Text(
                  'Web Not Supported',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 16),
                Text(
                  'Kylan Connect uses direct device-to-device networking which is not available in web browsers. Please use the Android, iOS, or desktop app.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class KylanConnectApp extends ConsumerWidget {
  const KylanConnectApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'Kylan Connect',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      onGenerateRoute: AppRouter.onGenerateRoute,
      initialRoute: '/',
    );
  }
}
