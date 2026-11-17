/// M-05 · Orquestador de la lectura OCR: tiempo límite de 10 s,
/// cancelación inmediata y un solo resultado por petición (RF-23, RF-29 a
/// RF-31; RNF-13; CA-064, CA-074, CA-077 a CA-082, CA-145).
library;

import 'dart:async';
import 'dart:typed_data';

import '../../config/app_config.dart';
import '../../core/error_logger.dart';
import '../../core/result.dart';
import 'ocr_adapter.dart';
import 'receipt_parser.dart';

export 'ocr_adapter.dart' show OcrFailureKind;
export 'receipt_parser.dart' show ParsedReceipt, ReceiptField;

/// Mensajes no técnicos de la lectura (RNF-05). Todos dicen que la foto se
/// conserva y qué hacer.
class OcrMessages {
  OcrMessages._();

  static const String noConnection =
      'No hay conexión a internet para leer el recibo. Revisa tu conexión y '
      'toca "Reintentar", o registra el movimiento a mano; la foto se '
      'conserva.';
  static const String timeout =
      'La lectura del recibo tardó demasiado. Toca "Reintentar" o registra '
      'el movimiento a mano; la foto se conserva.';
  static const String server =
      'El servicio que lee los recibos no respondió bien. Toca "Reintentar" '
      'o registra el movimiento a mano; la foto se conserva.';
  static const String notConfigured =
      'La lectura automática de recibos no está disponible en esta versión. '
      'Registra el movimiento a mano; la foto se conserva.';
  static const String illegible =
      'No se pudo leer el recibo. Toma la foto de nuevo con buena luz y el '
      'recibo completo, o registra el movimiento a mano con esta foto.';

  static String forKind(OcrFailureKind kind) => switch (kind) {
        OcrFailureKind.noConnection => noConnection,
        OcrFailureKind.timeout => timeout,
        OcrFailureKind.server => server,
        OcrFailureKind.notConfigured => notConfigured,
      };
}

/// Resultado de una lectura.
sealed class OcrOutcome {
  const OcrOutcome();
}

/// Se leyó al menos un campo. [elapsed] sirve para medir RNF-13.
final class OcrRead extends OcrOutcome {
  const OcrRead(this.receipt, this.elapsed);
  final ParsedReceipt receipt;
  final Duration elapsed;
}

/// La imagen no se pudo leer (RF-29).
final class OcrIllegible extends OcrOutcome {
  const OcrIllegible(this.elapsed);
  final Duration elapsed;
}

/// Sin internet, error del servicio o tiempo agotado (RF-30).
final class OcrFailed extends OcrOutcome {
  const OcrFailed(this.kind, this.error);
  final OcrFailureKind kind;
  final AppError error;
}

/// La persona canceló (RF-31).
final class OcrCancelled extends OcrOutcome {
  const OcrCancelled();
}

/// Una lectura en curso. [result] se completa una sola vez: con lo que
/// llegue primero entre la respuesta, el tiempo límite y la cancelación
/// (CA-082). Lo que llegue después se ignora (CA-081).
class OcrRequest {
  OcrRequest._();

  final Completer<OcrOutcome> _completer = Completer<OcrOutcome>();
  final OcrCancelToken _token = OcrCancelToken();
  Timer? _timer;

  Future<OcrOutcome> get result => _completer.future;
  bool get isDone => _completer.isCompleted;

  /// Detiene la petición de inmediato (RF-31).
  void cancel() => _finish(const OcrCancelled());

  /// Devuelve `true` si [outcome] fue el resultado final.
  bool _finish(OcrOutcome outcome) {
    if (_completer.isCompleted) return false;
    _timer?.cancel();
    _completer.complete(outcome);
    _token.cancel();
    return true;
  }
}

/// Orquesta el adaptador y el intérprete.
class OcrService {
  OcrService({
    required OcrAdapter adapter,
    required ErrorLogger logger,
    ReceiptParser? parser,
    Duration timeout = AppConfig.ocrTimeout,
  })  : _adapter = adapter,
        _logger = logger,
        _parser = parser ?? ReceiptParser(),
        _timeout = timeout;

  static const String module = 'M-05';

  final OcrAdapter _adapter;
  final ErrorLogger _logger;
  final ReceiptParser _parser;
  final Duration _timeout;

  /// Envía solo [image] (la foto comprimida, RNF-17) y empieza a contar
  /// los 10 s (RF-30).
  OcrRequest start(Uint8List image) {
    final request = OcrRequest._();
    final watch = Stopwatch()..start();
    request._timer = Timer(_timeout, () {
      _fail(request, const OcrException(OcrFailureKind.timeout));
    });
    _adapter.recognize(image, request._token).then<void>(
      (text) {
        request._finish(_interpret(text, watch.elapsed));
      },
      onError: (Object e) {
        _fail(request, e);
      },
    );
    return request;
  }

  OcrOutcome _interpret(String text, Duration elapsed) {
    final receipt = _parser.parse(text);
    return receipt.illegible
        ? OcrIllegible(elapsed)
        : OcrRead(receipt, elapsed);
  }

  /// Termina con error y lo registra, solo si nadie terminó antes.
  void _fail(OcrRequest request, Object e) {
    final kind = e is OcrException ? e.kind : OcrFailureKind.server;
    final error = AppError(
      type: ErrorType.ocr,
      message: OcrMessages.forKind(kind),
    );
    if (request._finish(OcrFailed(kind, error))) {
      _logger.log(type: ErrorType.ocr, module: module, cause: e);
    }
  }
}
