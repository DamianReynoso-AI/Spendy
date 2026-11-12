/// M-01 · Revisión y confirmación de los datos leídos del recibo (RF-24 a
/// RF-28; CA-062, CA-063, CA-066 a CA-073).
///
/// Siempre se muestra después de una lectura exitosa: los campos leídos
/// vienen prellenados, los vacíos resaltados y, si la fecha se cambió por
/// la de hoy, con aviso. Nada se guarda hasta que la persona toca
/// "Guardar" (RF-25, CA-068, CA-069); entonces M-02 valida y guarda el
/// egreso con su recibo de forma atómica (CA-066, CA-067, CA-072).
///
/// Solo usa M-02, M-03 y M-04; nunca `lib/data/` (RNF-30).
library;

import 'package:flutter/material.dart';

import '../../modules/categories/category_catalog.dart';
import '../../modules/movements/movement_service.dart';
import '../../modules/ocr/ocr_service.dart';
import '../../modules/receipts/camera_service.dart';
import '../../modules/receipts/receipt_service.dart';
import 'movement_form_screen.dart';

/// Textos de la revisión.
class OcrReviewTexts {
  OcrReviewTexts._();

  static const String title = 'Revisar recibo';
  static const String intro =
      'Revisa los datos leídos del recibo y corrige lo necesario. Elige la '
      'categoría y el método de pago. Nada se guarda hasta que toques '
      '"Guardar".';
  static const String notRead = 'No se pudo leer; escríbelo.';
  static const String dateWarning =
      'No se pudo leer una fecha válida (o era futura); se puso la de hoy. '
      'Revísala.';
}

/// Convierte lo leído en los valores iniciales del formulario.
MovementPrefill prefillFromReading(ParsedReceipt reading) {
  final missing = reading.missing;
  return MovementPrefill(
    amountText: reading.amountText,
    date: reading.date,
    description: reading.merchant,
    hints: {
      if (missing.contains(ReceiptField.total))
        MovementFields.amount: OcrReviewTexts.notRead,
      if (reading.dateWarning) MovementFields.date: OcrReviewTexts.dateWarning,
      if (missing.contains(ReceiptField.merchant))
        MovementFields.description: OcrReviewTexts.notRead,
    },
  );
}

/// Pantalla de revisión. Regresa `true` si se guardó.
class OcrReviewScreen extends StatelessWidget {
  const OcrReviewScreen({
    super.key,
    required this.service,
    required this.catalog,
    required this.photo,
    required this.reading,
    this.receipts,
    this.camera,
    this.clock,
  });

  final MovementService service;
  final CategoryCatalog catalog;
  final TempReceipt photo;
  final ParsedReceipt reading;
  final ReceiptService? receipts;
  final CameraService? camera;
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) {
    return MovementFormScreen(
      service: service,
      catalog: catalog,
      receipts: receipts,
      camera: camera,
      clock: clock,
      initialReceipt: photo,
      prefill: prefillFromReading(reading),
      title: OcrReviewTexts.title,
      introText: OcrReviewTexts.intro,
    );
  }
}
