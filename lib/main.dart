import 'package:flutter/material.dart';

import 'screens/company_list_screen.dart';
import 'screens/search_screen.dart';
import 'widgets/update_banner.dart';

void main() {
  runApp(const HvacLeadsApp());
}

class HvacLeadsApp extends StatelessWidget {
  const HvacLeadsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HVAC Leads',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E6F64)),
        useMaterial3: true,
      ),
      home: const UpdateBanner(child: HomeShell()),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _tabs = [
    SearchScreen(),
    CompanyListScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
          NavigationDestination(icon: Icon(Icons.business), label: 'Companies'),
        ],
      ),
    );
  }
}
