/// M-04 · Recibos: compresión, captura temporal, vinculación, reemplazo y
/// descarte (RF-18 a RF-22; RNF-12, RNF-14, RNF-21; CA-041, CA-043,
/// CA-050 a CA-061).
///
/// En el incremento 4 conecta la foto aceptada con la lectura OCR (M-05,
/// RF-23).
///
/// Es lo único que la interfaz usa para recibos; las pantallas nunca
/// importan `lib/data/` (RNF-30).
library;

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../config/app_config.dart';
import '../../core/error_logger.dart';
import '../../core/result.dart';
import '../../data/image_store.dart';
import '../../data/models/receipt.dart';
import '../../data/repositories/receipt_repository.dart';
import '../ocr/ocr_service.dart';

/// Una foto que aún no se guarda con un egreso. Vive en `temp_recibos/`.
class TempReceipt {
  const TempReceipt({
    required this.path,
    required this.sizeBytes,
    required this.capturedAt,
    this.compressed = false,
  });

  /// Ruta absoluta, para mostrar la vista previa.
  final String path;
  final int sizeBytes;
  final DateTime capturedAt;

  /// `true` cuando ya pasó por [compressReceiptImage] ("Usar foto").
  final bool compressed;

  /// Lo que necesita M-11 para el guardado atómico.
  PendingReceipt toPending() => PendingReceipt(
        file: File(path),
        sizeBytes: sizeBytes,
        capturedAt: capturedAt,
      );
}

/// El recibo de un egreso guardado, para el detalle (RF-19).
class ReceiptView {
  const ReceiptView({required this.path, required this.exists});

  final String path;

  /// `false` si el archivo ya no está en la ruta registrada (CA-051).
  final bool exists;
}

/// Mensajes de recibos para la persona usuaria (RNF-05).
class ReceiptMessages {
  ReceiptMessages._();

  static const String storageFull =
      'No hay espacio libre en el teléfono para guardar la foto. Libera '
      'espacio (por ejemplo, borra fotos o apps que no uses) y vuelve a '
      'intentarlo.';
  static const String processFailed =
      'No se pudo preparar la foto. Toca "Repetir" para tomarla de nuevo.';
  static const String saveFailed =
      'No se pudo guardar el recibo por un problema con el almacenamiento '
      'del teléfono. El movimiento no cambió; intenta de nuevo.';
  static const String loadFailed =
      'No se pudo leer el recibo. Cierra y vuelve a abrir el detalle.';
  static const String missingFile =
      'No se encontró la imagen de este recibo en el teléfono. El '
      'movimiento sigue guardado; puedes reemplazar el recibo con una foto '
      'nueva.';
}

/// Convierte una imagen en un JPEG de [maxBytes] o menos (RNF-12, CA-043):
/// endereza la foto según su EXIF, limita el lado mayor a [maxSide] y baja
/// la calidad (y si hace falta, el tamaño) hasta que cabe. Volver a
/// codificar también quita los metadatos EXIF, como la ubicación.
/// Lanza [FormatException] si [input] no es una imagen.
Uint8List compressReceiptImage(
  Uint8List input, {
  int maxBytes = AppConfig.maxReceiptBytes,
  int maxSide = AppConfig.receiptMaxSidePx,
  List<int> qualities = AppConfig.receiptJpegQualities,
}) {
  final decoded = img.decodeImage(input);
  if (decoded == null) {
    throw const FormatException('El archivo no es una imagen');
  }
  var image = _limitSide(img.bakeOrientation(decoded), maxSide);
  while (true) {
    for (final quality in qualities) {
      final bytes = img.encodeJpg(image, quality: quality);
      if (bytes.length <= maxBytes) return bytes;
    }
    final next = (_longestSide(image) * 0.8).floor();
    if (next < 64) {
      throw const FormatException('No se pudo comprimir la imagen');
    }
    image = _limitSide(image, next);
  }
}

int _longestSide(img.Image image) =>
    image.width > image.height ? image.width : image.height;

img.Image _limitSide(img.Image image, int maxSide) {
  if (_longestSide(image) <= maxSide) return image;
  return image.width >= image.height
      ? img.copyResize(image, width: maxSide)
      : img.copyResize(image, height: maxSide);
}

/// Comprime en otro hilo para no congelar la interfaz.
Future<Uint8List> compressInBackground(Uint8List bytes) =>
    Isolate.run(() => compressReceiptImage(bytes));

typedef ImageCompressor = Future<Uint8List> Function(Uint8List bytes);

/// Lógica de recibos de M-04.
class ReceiptService {
  ReceiptService({
    required ImageStore store,
    required ReceiptRepository repository,
    required ErrorLogger logger,
    ImageCompressor? compressor,
    DateTime Function()? clock,
    OcrService? ocr,
  })  : _ocr = ocr,
        _store = store,
        _repository = repository,
        _logger = logger,
        _compress = compressor ?? compressInBackground,
        _clock = clock ?? DateTime.now;

  static const String module = 'M-04';

  final ImageStore _store;
  final ReceiptRepository _repository;
  final ErrorLogger _logger;
  final ImageCompressor _compress;
  final DateTime Function() _clock;
  final OcrService? _ocr;

  /// `true` si hay lectura OCR conectada (incremento 4).
  bool get canRead => _ocr != null;

  /// Envía la foto ya aceptada (comprimida) a la lectura OCR y devuelve la
  /// petición en curso, que se puede cancelar (RF-23, RF-31). Solo se
  /// envía la imagen (RNF-17).
  Future<Result<OcrRequest>> startReading(TempReceipt photo) async {
    final ocr = _ocr;
    if (ocr == null) throw StateError('ReceiptService sin OcrService');
    try {
      return Success(ocr.start(await File(photo.path).readAsBytes()));
    } on Object catch (e) {
      await _log(ErrorType.storageRead, e);
      return const Failure(
        AppError(
          type: ErrorType.storageRead,
          message: ReceiptMessages.processFailed,
        ),
      );
    }
  }

  /// Pasa la foto recién tomada a `temp_recibos/` para la vista previa
  /// (RF-18). Si no hay espacio, no queda nada a medias (CA-059).
  Future<Result<TempReceipt>> storeCapture(String capturedPath) async {
    try {
      final file = await _store.importCapture(capturedPath);
      return Success(await _temp(file, compressed: false));
    } on Object catch (e) {
      await _store.deleteQuietly(File(capturedPath));
      return Failure(await _failure(e, ReceiptMessages.saveFailed));
    }
  }

  /// "Usar foto": comprime a 1.5 MB o menos y reemplaza la captura
  /// original por la comprimida (RNF-12, CA-043).
  Future<Result<TempReceipt>> accept(TempReceipt raw) async {
    if (raw.compressed) return Success(raw);
    final rawFile = File(raw.path);
    try {
      final bytes = await _compress(await rawFile.readAsBytes());
      final file = await _store.writeTemp(bytes);
      await _store.deleteQuietly(rawFile);
      return Success(await _temp(file, compressed: true));
    } on FormatException catch (e) {
      await _log(ErrorType.unexpected, e);
      return const Failure(
        AppError(
          type: ErrorType.unexpected,
          message: ReceiptMessages.processFailed,
        ),
      );
    } on Object catch (e) {
      return Failure(await _failure(e, ReceiptMessages.saveFailed));
    }
  }

  /// "Repetir" o "Descartar": borra la foto temporal (CA-041, CA-057).
  Future<void> discard(TempReceipt temp) =>
      _store.deleteQuietly(File(temp.path));

  /// El recibo del egreso [movementId], o `null` si no tiene (RF-19).
  Future<Result<ReceiptView?>> receiptOf(int movementId) async {
    try {
      final receipt = await _repository.findByMovement(movementId);
      if (receipt == null) return const Success(null);
      final file = _store.resolve(receipt.filePath);
      return Success(
        ReceiptView(path: file.path, exists: await file.exists()),
      );
    } on Object catch (e) {
      final error = translateStorageError(e, writing: false);
      await _log(error.type, e);
      return const Failure(
        AppError(
          type: ErrorType.storageRead,
          message: ReceiptMessages.loadFailed,
        ),
      );
    }
  }

  /// Agrega o reemplaza el recibo de un egreso ya guardado (RF-20,
  /// CA-053, CA-055). Si falla, el recibo anterior sigue igual.
  Future<Result<void>> attach(int movementId, TempReceipt temp) async {
    final accepted = await accept(temp);
    if (accepted case Failure(:final error)) return Failure(error);
    try {
      await _repository.attach(movementId, accepted.valueOrNull!.toPending());
      return const Success(null);
    } on Object catch (e) {
      return Failure(await _failure(e, ReceiptMessages.saveFailed));
    }
  }

  /// Quita el recibo y borra su archivo (RF-20, CA-054).
  Future<Result<void>> remove(int movementId) async {
    try {
      await _repository.remove(movementId);
      return const Success(null);
    } on Object catch (e) {
      return Failure(await _failure(e, ReceiptMessages.saveFailed));
    }
  }

  /// Al iniciar la app: borra temporales y archivos sin registro (TEC-06).
  /// Nunca impide abrir la app; si falla, solo se registra.
  Future<int> cleanOrphans() async {
    try {
      return await _store.cleanOrphanImages(await _repository.allPaths());
    } on Object catch (e) {
      await _log(ErrorType.storageWrite, e);
      return 0;
    }
  }

  Future<TempReceipt> _temp(File file, {required bool compressed}) async =>
      TempReceipt(
        path: file.path,
        sizeBytes: await file.length(),
        capturedAt: _clock(),
        compressed: compressed,
      );

  /// Traduce el fallo, lo registra sin datos del usuario y elige el
  /// mensaje: sin espacio (RF-22, CA-059) o [fallback].
  Future<AppError> _failure(Object e, String fallback) async {
    final error = translateStorageError(e, writing: true);
    await _log(error.type, e);
    final full = error.type == ErrorType.storageFull;
    return AppError(
      type: error.type,
      message: full ? ReceiptMessages.storageFull : fallback,
    );
  }

  Future<void> _log(ErrorType type, Object e) =>
      _logger.log(type: type, module: module, cause: e);
}
