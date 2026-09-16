import 'package:flutter/material.dart';

import 'showcase_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WidgetShowcaseApp());
}

class WidgetShowcaseApp extends StatelessWidget {
  const WidgetShowcaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'shader_fun - WidgetChannel Showcase',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF090A0F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1),
          secondary: Color(0xFF06B6D4),
          surface: Color(0xFF13151F),
        ),
      ),
      home: const WidgetShowcaseScreen(),
    );
  }
}
