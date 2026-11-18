/// M-10 · Aviso de privacidad para volver a leerlo desde Ajustes (AUD-07).
library;

import 'package:flutter/material.dart';

import '../../config/privacy_texts.dart';

/// Muestra el mismo texto que el primer inicio, solo para leer.
class PrivacyNoticeScreen extends StatelessWidget {
  const PrivacyNoticeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text(PrivacyTexts.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            for (final paragraph in PrivacyTexts.paragraphs) ...[
              Text(paragraph, style: textTheme.bodyLarge),
              const SizedBox(height: 12),
            ],
            Text('Versión ${PrivacyTexts.version} del aviso.',
                style: textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
