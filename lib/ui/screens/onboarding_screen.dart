/// M-01 · Pantalla obligatoria de primer inicio con el aviso de privacidad
/// (RF-51; CA-141 a CA-143).
///
/// No tiene botón de regresar: hasta tocar "Acepto" no se puede usar el
/// resto de la app (CA-142). Solo usa M-10; nunca `lib/data/` (RNF-30).
library;

import 'package:flutter/material.dart';

import '../../config/privacy_texts.dart';
import '../../core/result.dart';
import '../../modules/privacy/onboarding_service.dart';

/// Aviso de privacidad. [onAccepted] se llama cuando la aceptación ya
/// quedó guardada.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.service,
    required this.onAccepted,
  });

  final OnboardingService service;
  final VoidCallback onAccepted;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _saving = false;
  String? _error;

  Future<void> _accept() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await widget.service.accept();
    if (!mounted) return;
    switch (result) {
      case Success():
        widget.onAccepted();
      case Failure(:final error):
        setState(() {
          _saving = false;
          _error = error.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(PrivacyTexts.title),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(PrivacyTexts.intro, style: textTheme.titleMedium),
              const SizedBox(height: 16),
              for (final paragraph in PrivacyTexts.paragraphs) ...[
                Text(paragraph, style: textTheme.bodyLarge),
                const SizedBox(height: 12),
              ],
              if (_error != null) ...[
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _saving ? null : _accept,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text(PrivacyTexts.acceptButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
