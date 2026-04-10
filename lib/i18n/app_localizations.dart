import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

// ignore: depend_on_referenced_packages
import 'package:intl/intl.dart' as intl;

/// Generated localizations class.
///
/// In production, run `flutter gen-l10n` with the ARB files in lib/i18n/
/// and a l10n.yaml pointing to them. This stub allows compilation without
/// the code-generator output present.
///
/// Replace this file with the generated output once `flutter gen-l10n` has run.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      [delegate];

  static const List<Locale> supportedLocales = [
    Locale('de'),
    Locale('en'),
  ];

  // Navigation
  String get navChat;
  String get navDocuments;
  String get navSettings;

  // Chat
  String get chatPlaceholder;
  String get chatSend;
  String get chatThinking;
  String get chatNewSession;
  String get chatEmptyTitle;
  String get chatEmptySubtitle;

  // Documents
  String get docsImport;
  String get docsProcessing;
  String get docsReady;
  String get docsChunks;
  String get docsIndexed;

  // Setup
  String get setupWelcome;
  String get setupTagline;
  String get setupLanguageLabel;
  String get setupModelChoose;
  String get setupModelHint;
  String get setupGpuLabel;
  String get setupDownloading;
  String get setupDownloadButton;
  String get setupStartButton;
  String get setupContinue;
  String get setupFinish;

  // App / Loading
  String get appSubtitle;
  String get loadingModelMessage;
  String get loadingModelSubtitle;
  String get buttonRetry;

  // Settings
  String get settingsModel;
  String get settingsModelNotLoaded;
  String get settingsGpu;
  String get settingsGpuAuto;
  String get settingsGpuForce;
  String get settingsGpuCpu;
  String get settingsLanguage;
  String get settingsReset;
}

class _AppLocalizationsDe extends AppLocalizations {
  _AppLocalizationsDe() : super('de');

  @override String get navChat => 'Chat';
  @override String get navDocuments => 'Dokumente';
  @override String get navSettings => 'Einstellungen';
  @override String get chatPlaceholder => 'Nachricht eingeben...';
  @override String get chatSend => 'Senden';
  @override String get chatThinking => 'Denkt nach...';
  @override String get chatNewSession => 'Neues Gespräch';
  @override String get chatEmptyTitle => 'Bereit zum Chatten';
  @override String get chatEmptySubtitle =>
      'Ihre KI läuft lokal.\nKeine Daten verlassen Ihr Gerät.';
  @override String get docsImport => 'Dokument importieren';
  @override String get docsProcessing => 'Verarbeite';
  @override String get docsReady => 'Dokument bereit';
  @override String get docsChunks => 'Abschnitte';
  @override String get docsIndexed => 'im lokalen Index';
  @override String get setupWelcome => 'Willkommen bei InHausKI';
  @override String get setupTagline => 'Ihre KI. Ihr Gerät. Kein Internet.';
  @override String get setupLanguageLabel => 'Sprache / Language';
  @override String get setupModelChoose => 'KI-Modell wählen';
  @override String get setupModelHint => 'Das Modell wird einmalig heruntergeladen (~1.5 GB). Danach läuft alles offline.';
  @override String get setupGpuLabel => 'GPU-Beschleunigung';
  @override String get setupDownloading => 'KI-Modell laden';
  @override String get setupDownloadButton => 'Herunterladen';
  @override String get setupStartButton => 'Los geht\'s';
  @override String get setupContinue => 'Weiter';
  @override String get setupFinish => 'Fertig';
  @override String get appSubtitle => 'Offline KI-Assistent';
  @override String get loadingModelMessage => 'Lade Gemma 4 2B...';
  @override String get loadingModelSubtitle => 'Dies kann beim ersten Start einige Minuten dauern.';
  @override String get buttonRetry => 'Erneut versuchen';
  @override String get settingsModel => 'KI-Modell';
  @override String get settingsModelNotLoaded => 'Nicht geladen';
  @override String get settingsGpu => 'GPU-Beschleunigung';
  @override String get settingsGpuAuto => 'Automatisch';
  @override String get settingsGpuForce => 'Immer GPU';
  @override String get settingsGpuCpu => 'Nur CPU';
  @override String get settingsLanguage => 'Sprache';
  @override String get settingsReset => 'Setup zurücksetzen';
}

class _AppLocalizationsEn extends AppLocalizations {
  _AppLocalizationsEn() : super('en');

  @override String get navChat => 'Chat';
  @override String get navDocuments => 'Documents';
  @override String get navSettings => 'Settings';
  @override String get chatPlaceholder => 'Type a message...';
  @override String get chatSend => 'Send';
  @override String get chatThinking => 'Thinking...';
  @override String get chatNewSession => 'New conversation';
  @override String get chatEmptyTitle => 'Ready to chat';
  @override String get chatEmptySubtitle =>
      'Your AI runs locally.\nNo data ever leaves your device.';
  @override String get docsImport => 'Import document';
  @override String get docsProcessing => 'Processing';
  @override String get docsReady => 'Document ready';
  @override String get docsChunks => 'chunks';
  @override String get docsIndexed => 'in local index';
  @override String get setupWelcome => 'Welcome to InHausKI';
  @override String get setupTagline => 'Your AI. Your device. No internet.';
  @override String get setupLanguageLabel => 'Language';
  @override String get setupModelChoose => 'Choose AI model';
  @override String get setupModelHint => 'The model is downloaded once (~1.5 GB) and then runs fully offline.';
  @override String get setupGpuLabel => 'GPU Acceleration';
  @override String get setupDownloading => 'Loading AI model';
  @override String get setupDownloadButton => 'Download';
  @override String get setupStartButton => 'Let\'s go';
  @override String get setupContinue => 'Continue';
  @override String get setupFinish => 'Finish';
  @override String get appSubtitle => 'Offline AI Assistant';
  @override String get loadingModelMessage => 'Loading Gemma 4 2B...';
  @override String get loadingModelSubtitle => 'This may take a few minutes on first run.';
  @override String get buttonRetry => 'Retry';
  @override String get settingsModel => 'AI Model';
  @override String get settingsModelNotLoaded => 'Not loaded';
  @override String get settingsGpu => 'GPU Acceleration';
  @override String get settingsGpuAuto => 'Automatic';
  @override String get settingsGpuForce => 'Always GPU';
  @override String get settingsGpuCpu => 'CPU only';
  @override String get settingsLanguage => 'Language';
  @override String get settingsReset => 'Reset setup';
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    final String localeName = intl.Intl.canonicalizedLocale(locale.toString());
    if (localeName.startsWith('de')) {
      return SynchronousFuture<AppLocalizations>(_AppLocalizationsDe());
    }
    return SynchronousFuture<AppLocalizations>(_AppLocalizationsEn());
  }

  @override
  bool isSupported(Locale locale) =>
      ['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
