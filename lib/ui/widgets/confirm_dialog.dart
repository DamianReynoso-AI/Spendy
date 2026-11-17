/// M-01 · Diálogo modal de confirmación reutilizable (RF-20, RF-21).
library;

import 'package:flutter/material.dart';

/// Muestra un diálogo modal con "Cancelar" y [confirmLabel]. Devuelve
/// `true` solo si la persona confirma; tocar fuera no lo cierra, para que
/// la decisión sea explícita.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String content,
  required String confirmLabel,
  String cancelLabel = 'Cancelar',
  bool destructive = true,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      final colors = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            child: Text(cancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: destructive ? colors.error : null,
              foregroundColor: destructive ? colors.onError : null,
              minimumSize: const Size(48, 48),
            ),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}
