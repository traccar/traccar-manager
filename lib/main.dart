import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rate_my_app/rate_my_app.dart';
import 'package:traccar_manager/main_screen.dart';
import 'package:traccar_manager/network_service.dart';
import 'package:traccar_manager/network_snackbar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  runApp(MainApp());
}

final GlobalKey<ScaffoldMessengerState> messengerKey =
    GlobalKey<ScaffoldMessengerState>();

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  final RateMyApp _rateMyApp = RateMyApp();
  final NetworkService _networkService = NetworkService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _rateMyApp.init();
      if (mounted && _rateMyApp.shouldOpenDialog) {
        _rateMyApp.showRateDialog(context);
      }
      _networkService.startListening(
        onConnected: () {
          hideInternetSnackbar(messengerKey);
        },
        onDisconnected: () {
          showNoInternetSnackbar(messengerKey);
        },
      );
    });
  }

  @override
  void dispose() {
    _networkService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: messengerKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
      ),
      home: MainScreen(),
      builder: (context, child) {
        final brightness = MediaQuery.of(context).platformBrightness;
        SystemChrome.setSystemUIOverlayStyle(
          SystemUiOverlayStyle(
            statusBarIconBrightness:
                brightness == Brightness.dark
                    ? Brightness.light
                    : Brightness.dark,
          ),
        );
        return child!;
      },
    );
  }
}
