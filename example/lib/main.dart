import 'package:flutter/material.dart';

import 'shadertoy_studio.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ShaderToyApp());
}

class ShaderToyApp extends StatelessWidget {
  const ShaderToyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'shader_fun example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0F12),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF5500),
          secondary: Color(0xFF00E5FF),
          surface: Color(0xFF181822),
        ),
      ),
      home: const ShaderToyStudio(),
    );
  }
}
