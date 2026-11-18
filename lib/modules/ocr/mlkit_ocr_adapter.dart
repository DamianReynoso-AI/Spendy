/// M-05 · Proveedor de OCR en el teléfono con Google ML Kit Text
/// Recognition (RNF-32; ver docs/arquitectura.md, sección 5.2).
///
/// La foto se lee en el mismo teléfono con el modelo de texto latino que
/// viene dentro del APK: no se envía a ningún servidor, no necesita clave
/// ni internet y no tiene costo (RNF-17, RNF-18).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;

import 'ocr_adapter.dart';
import 'ocr_layout.dart';

/// Lee una imagen guardada en [path] y devuelve sus renglones de texto.
typedef LineReader = Future<List<TextFragment>> Function(String path);

/// Adaptador de ML Kit. [readLines] se puede sustituir en pruebas.
class MlKitOcrAdapter implements OcrAdapter {
  MlKitOcrAdapter({required this.workDir, LineReader? readLines})
      : _readLines = readLines ?? _mlKitLines;

  /// Carpeta privada de la app donde se deja un momento la foto, porque
  /// ML Kit lee desde archivo. Se borra al terminar.
  final Directory workDir;
  final LineReader _readLines;

  static TextRecognizer? _recognizer;

  /// Si ML Kit falla, el error original sube tal cual: [OcrService] lo
  /// registra en la bitácora con su causa y muestra el mensaje no técnico.
  @override
  Future<String> recognize(Uint8List image, OcrCancelToken cancel) async {
    final file = File(
      p.join(workDir.path, 'ocr_${DateTime.now().microsecondsSinceEpoch}.jpg'),
    );
    try {
      await file.writeAsBytes(image, flush: true);
      final fragments = await _readLines(file.path);
      if (cancel.isCancelled) throw const OcrException(OcrFailureKind.server);
      return joinFragmentsIntoLines(fragments);
    } finally {
      if (file.existsSync()) file.deleteSync();
    }
  }

  static Future<List<TextFragment>> _mlKitLines(String path) async {
    final recognizer =
        _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    final result = await recognizer.processImage(InputImage.fromFilePath(path));
    return [
      for (final block in result.blocks)
        for (final line in block.lines)
          TextFragment(
            line.text,
            line.boundingBox.left,
            line.boundingBox.top,
            line.boundingBox.right,
            line.boundingBox.bottom,
          ),
    ];
  }
}
