import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'services/llama_service.dart';
import 'services/locale_service.dart';
import 'services/rag_service.dart';
import 'storage/app_database.dart';
import 'storage/chat_history.dart';
import 'screens/chat_screen.dart';
import 'screens/documents_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/setup_wizard.dart';
import 'screens/loading_screen.dart';
import 'i18n/app_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const InHausKIApp());
}

class InHausKIApp extends StatelessWidget {
  const InHausKIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocaleService()),
        ChangeNotifierProvider(create: (_) => LlamaService()),
        ChangeNotifierProxyProvider<LlamaService, RagService>(
          create: (context) => RagService(context.read<LlamaService>()),
          update: (context, llamaService, ragService) =>
              ragService ?? RagService(llamaService),
        ),
        // AppDatabase is a plain object (not ChangeNotifier); expose via Provider.
        Provider<AppDatabase>(
          create: (_) => AppDatabase(),
          dispose: (_, db) => db.close(),
        ),
        ChangeNotifierProxyProvider<AppDatabase, ChatHistory>(
          create: (context) => ChatHistory(context.read<AppDatabase>()),
          update: (context, db, history) => history ?? ChatHistory(db),
        ),
      ],
      child: Consumer2<LlamaService, LocaleService>(
        builder: (context, llama, localeService, _) {
          return MaterialApp(
            title: 'InHausKI',
            debugShowCheckedModeBanner: false,
            theme: _buildTheme(),
            darkTheme: _buildDarkTheme(),
            themeMode: ThemeMode.system,
            // null → follow system locale; non-null → user override
            locale: localeService.locale,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [
              Locale('de'), // German
              Locale('en'), // English
            ],
            home: !llama.isSetupComplete
                ? const SetupWizard()
                : llama.isModelLoaded
                    ? const MainShell()
                    : const LoadingScreen(),
          );
        },
      ),
    );
  }

  ThemeData _buildTheme() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1A73E8), // InHausKI blue
        brightness: Brightness.light,
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1A73E8),
        brightness: Brightness.dark,
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    ChatScreen(),
    DocumentsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.chat_bubble_outline),
            selectedIcon: const Icon(Icons.chat_bubble),
            label: loc.navChat,
          ),
          NavigationDestination(
            icon: const Icon(Icons.folder_open),
            selectedIcon: const Icon(Icons.folder),
            label: loc.navDocuments,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: loc.navSettings,
          ),
        ],
      ),
    );
  }
}
