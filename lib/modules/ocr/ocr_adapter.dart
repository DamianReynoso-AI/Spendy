/// M-05 · Contrato del proveedor de OCR (RNF-32).
///
/// Cambiar de proveedor solo requiere otra implementación de [OcrAdapter];
/// ni la interfaz (M-01) ni la lógica de negocio cambian.
library;

import 'dart:typed_data';

/// Por qué falló la lectura. La interfaz lo convierte en un mensaje no
/// técnico (RNF-05).
enum OcrFailureKind {
  /// Sin internet o no se pudo conectar con el servicio.
  noConnection,

  /// El servicio respondió con error o con una respuesta que no se entiende.
  server,

  /// Pasaron los 10 segundos de [AppConfig.ocrTimeout] (RF-30).
  timeout,

  /// Esta versión no tiene configurado el servicio (sin endpoint o clave).
  notConfigured,
}

/// Fallo controlado de un [OcrAdapter].
class OcrException implements Exception {
  const OcrException(this.kind);

  final OcrFailureKind kind;

  @override
  String toString() => 'OcrException: ${kind.name}';
}

/// Permite detener una petición en curso (RF-31). Las implementaciones
/// registran con [onCancel] lo que deben hacer al cancelar (por ejemplo,
/// cerrar la conexión).
class OcrCancelToken {
  final List<void Function()> _callbacks = [];
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  /// Si ya se canceló, [callback] corre de inmediato.
  void onCancel(void Function() callback) {
    if (_cancelled) {
      callback();
    } else {
      _callbacks.add(callback);
    }
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final callback in _callbacks) {
      callback();
    }
    _callbacks.clear();
  }
}

/// Un proveedor de OCR: recibe solo los bytes de la imagen comprimida y
/// devuelve el texto leído (RNF-17). Lanza [OcrException] si falla.
abstract interface class OcrAdapter {
  Future<String> recognize(Uint8List image, OcrCancelToken cancel);
}

/// Adaptador para cuando no hay proveedor configurado: siempre falla con
/// [OcrFailureKind.notConfigured] y la persona registra a mano.
class UnconfiguredOcrAdapter implements OcrAdapter {
  const UnconfiguredOcrAdapter();

  @override
  Future<String> recognize(Uint8List image, OcrCancelToken cancel) =>
      Future.error(const OcrException(OcrFailureKind.notConfigured));
}
