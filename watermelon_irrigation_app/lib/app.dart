import 'package:flutter/material.dart';

import 'screens/analytics_screen.dart';
import 'screens/field_screen.dart';
import 'screens/home_screen.dart';
import 'screens/irrigation_screen.dart';
import 'state/field_controller.dart';
import 'theme/app_theme.dart';

class WatermelonIrrigationApp extends StatelessWidget {
  const WatermelonIrrigationApp({super.key, required this.controller});
  final FieldController controller;

  @override
  Widget build(BuildContext context) {
    return FieldScope(
      controller: controller,
      child: MaterialApp(
        title: 'Watermelon Irrigation',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const AppShell(),
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _screens = [
    HomeScreen(),
    IrrigationScreen(),
    AnalyticsScreen(),
    FieldScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.water_drop_outlined),
              selectedIcon: Icon(Icons.water_drop),
              label: 'Irrigation'),
          NavigationDestination(icon: Icon(Icons.show_chart), label: 'Analytics'),
          NavigationDestination(
              icon: Icon(Icons.eco_outlined), selectedIcon: Icon(Icons.eco), label: 'Field'),
        ],
      ),
    );
  }
}
