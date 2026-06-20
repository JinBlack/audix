import 'package:flutter/material.dart';

import 'features/home/home_screen.dart';

class AudixApp extends StatelessWidget {
  const AudixApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF5B4FCF);
    return MaterialApp(
      title: 'Audix',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
