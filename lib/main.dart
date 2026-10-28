import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'console_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const GeekConsoleApp());
}

class GeekConsoleApp extends StatelessWidget {
  const GeekConsoleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '极客运维控制台',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF1F6FEB),
          surface: Color(0xFF161B22),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Color(0xFF21262D),
          contentTextStyle: TextStyle(color: Color(0xFFE6EDF3)),
        ),
      ),
      home: const ConsolePage(),
    );
  }
}
