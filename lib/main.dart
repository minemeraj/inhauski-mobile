import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:objectbox/objectbox.dart';
import 'package:provider/provider.dart';

import 'services/embedding_service.dart';
import 'services/llama_service.dart';
import 'services/locale_service.dart';
import 'services/rag_service.dart';
import 'storage/app_database.dart';
import 'storage/chat_history.dart';
import 'storage/objectbox_store.dart';
import 'screens/chat_screen.dart';
import 'screens/documents_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/setup_wizard.dart';
import 'screens/loading_screen.dart';
import 'i18n/app_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Open ObjectBox store once at startup; it lives for the entire app session.
  final obStore = await ObjectBoxStore.open();

  runApp(InHausKIApp(objectBoxStore: obStore));
}

class InHausKIApp extends StatelessWidget {
  final ObjectBoxStore objectBoxStore;

  const InHausKIApp({super.key, required this.objectBoxStore});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // ── Locale / i18n ──────────────────────────────────────────────────
        ChangeNotifierProvider(create: (_) => LocaleService()),

        // ── LLM inference (chat) ───────────────────────────────────────────
        ChangeNotifierProvider(create: (_) => LlamaService()),

        // ── Embedding model (separate llama.cpp instance, embeddingMode=true)
        ChangeNotifierProvider(create: (_) => EmbeddingService()),

        // ── ObjectBox store (plain; not a ChangeNotifier) ──────────────────
        Provider<ObjectBoxStore>.value(value: objectBoxStore),

        // ── VectorChunk box (derived from store) ───────────────────────────
        ProxyProvider<ObjectBoxStore, Box<VectorChunk>>(
          update: (_, store, __) => store.vectorChunkBox,
        ),

        // ── RAG pipeline (depends on EmbeddingService + Box<VectorChunk>) ──
        ChangeNotifierProxyProvider2<EmbeddingService, Box<VectorChunk>,
            RagService>(
          create: (ctx) => RagService(
            ctx.read<EmbeddingService>(),
            ctx.read<Box<VectorChunk>>(),
          ),
          update: (ctx, embedSvc, box, prev) =>
              prev ?? RagService(embedSvc, box),
        ),

        // ── Drift SQLite (chat history) ────────────────────────────────────
        Provider<AppDatabase>(
          create: (_) => AppDatabase(),
          dispose: (_, db) => db.close(),
        ),
        ChangeNotifierProxyProvider<AppDatabase, ChatHistory>(
          create: (ctx) => ChatHistory(ctx.read<AppDatabase>()),
          update: (_, db, history) => history ?? ChatHistory(db),
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
              Locale('de'), // German (primary)
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
