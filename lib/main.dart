// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/background_service_manager.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // فقط init (configure) می‌کنیم — start نمی‌کنیم
  await BackgroundServiceManager.init();
  runApp(const PhoneBridgeApp());
}

class PhoneBridgeApp extends StatelessWidget {
  const PhoneBridgeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Bridge',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: const ColorScheme.dark(
            surface: Color(0xFF080B10),
            primary: Color(0xFF00F5C4),
          ),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      );
}