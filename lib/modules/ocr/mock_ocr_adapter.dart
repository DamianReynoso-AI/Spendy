/// M-05 · Proveedor de OCR simulado para pruebas (sin red).
library;

import 'dart:async';
import 'dart:typed_data';

import 'ocr_adapter.dart';

/// Devuelve [text] después de [delay], o lanza [error]. Respeta la
/// cancelación: si se cancela durante la espera, termina con
/// [OcrFailureKind.server] y nadie debe usar ese resultado (CA-081).
class MockOcrAdapter implements OcrAdapter {
  MockOcrAdapter({this.text = '', this.error, this.delay = Duration.zero});

  String text;
  Object? error;
  Duration delay;

  /// Cuántas veces se llamó y qué imágenes recibió (para verificar que
  /// solo se envía la imagen, RNF-17).
  final List<Uint8List> received = [];

  @override
  Future<String> recognize(Uint8List image, OcrCancelToken cancel) async {
    received.add(image);
    if (delay > Duration.zero) {
      final done = Completer<void>();
      final timer = Timer(delay, done.complete);
      cancel.onCancel(() {
        timer.cancel();
        if (!done.isCompleted) done.complete();
      });
      await done.future;
    }
    if (cancel.isCancelled) throw const OcrException(OcrFailureKind.server);
    final failure = error;
    if (failure != null) throw failure;
    return text;
  }
}
