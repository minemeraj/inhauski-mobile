import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/llama_service.dart';
import '../i18n/app_localizations.dart';

/// LoadingScreen displays while the Gemma 4 2B model is loading.
/// Once the model is fully initialized, the app navigates to MainShell.
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final llama = context.watch<LlamaService>();

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo / Icon
                Icon(
                  Icons.lock,
                  size: 80,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 32),

                // Title
                Text(
                  'InHausKI',
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),

                // Subtitle
                Text(
                  loc.appSubtitle, // "Offline AI Assistant"
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 64),

                // Loading spinner
                const SizedBox(
                  width: 60,
                  height: 60,
                  child: CircularProgressIndicator(
                    strokeWidth: 4,
                  ),
                ),
                const SizedBox(height: 32),

                // Status message
                Text(
                  llama.errorMessage ?? loc.loadingModelMessage,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                // Subtext
                if (llama.errorMessage == null)
                  Text(
                    loc.loadingModelSubtitle, // "This may take a few minutes on first run"
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                    textAlign: TextAlign.center,
                  ),

                // Error recovery button (if error occurred)
                if (llama.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 24.0),
                    child: ElevatedButton(
                      onPressed: () {
                        // Attempt to reload the model
                        if (llama.modelPath != null) {
                          llama.loadModel(llama.modelPath!);
                        }
                      },
                      child: Text(loc.buttonRetry),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
