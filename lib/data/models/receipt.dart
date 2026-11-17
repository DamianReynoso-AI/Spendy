/// M-11 · Modelo de un recibo tal como se guarda en la tabla `recibo`
/// (sección 13.4; RF-19, RF-20).
library;

import 'dart:io';

/// Un registro de la tabla `recibo`. [filePath] es relativo a la carpeta
/// privada de la app (por ejemplo, `recibos/1731430000000_42.jpg`), así la
/// ruta sigue siendo válida aunque cambie la carpeta base del sistema.
class Receipt {
  const Receipt({
    this.id,
    required this.movementId,
    required this.filePath,
    required this.sizeBytes,
    required this.capturedAt,
  });

  final int? id;
  final int movementId;
  final String filePath;
  final int sizeBytes;
  final DateTime capturedAt;

  Map<String, Object?> toRow() => {
        'movimiento_id': movementId,
        'ruta_archivo': filePath,
        'tamano_bytes': sizeBytes,
        'capturado_en': capturedAt.toIso8601String(),
      };

  factory Receipt.fromRow(Map<String, Object?> row) => Receipt(
        id: row['id'] as int?,
        movementId: row['movimiento_id'] as int,
        filePath: row['ruta_archivo'] as String,
        sizeBytes: row['tamano_bytes'] as int,
        capturedAt: DateTime.parse(row['capturado_en'] as String),
      );
}

/// Imagen ya comprimida que espera en `temp_recibos/` a que se guarde su
/// egreso (paso 1 del guardado atómico, RNF-21).
class PendingReceipt {
  const PendingReceipt({
    required this.file,
    required this.sizeBytes,
    required this.capturedAt,
  });

  final File file;
  final int sizeBytes;
  final DateTime capturedAt;
}
