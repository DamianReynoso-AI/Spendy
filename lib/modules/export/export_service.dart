/// M-08 · Escribe el archivo exportado y lo entrega al menú nativo de
/// compartir o guardar (RF-43, RF-44; RNF-11; CA-107, CA-111 a CA-113).
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../core/error_logger.dart';
import '../../core/result.dart';
import '../summary/annual_summary_calculator.dart';
import 'csv_exporter.dart';
import 'exporter.dart';
import 'pdf_exporter.dart';

export 'exporter.dart' show ExportFormat, exportFileName;

/// Mensajes de exportación (RNF-05).
class ExportMessages {
  ExportMessages._();

  static const String failed =
      'No se pudo exportar el resumen. Toca "Reintentar"; si sigue pasando, '
      'cierra y vuelve a abrir la app.';
  static const String storageFull =
      'No se pudo exportar porque el teléfono no tiene espacio libre. '
      'Libera espacio y toca "Reintentar".';
}

/// Entrega un archivo al menú de compartir del sistema.
typedef ShareLauncher = Future<void> Function(File file, ExportFormat format);

/// Menú nativo de compartir o guardar con `share_plus`.
Future<void> shareWithSystem(File file, ExportFormat format) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: format.mimeType)],
      fileNameOverrides: [p.basename(file.path)],
    ),
  );
}

/// Orquesta la exportación.
class ExportService {
  ExportService({
    required Future<Directory> Function() directory,
    required ErrorLogger logger,
    ShareLauncher share = shareWithSystem,
    DateTime Function()? clock,
    List<SummaryExporter> exporters = const [CsvExporter(), PdfExporter()],
  })  : _directory = directory,
        _logger = logger,
        _share = share,
        _clock = clock ?? DateTime.now,
        _exporters = {for (final e in exporters) e.format: e};

  static const String module = 'M-08';

  final Future<Directory> Function() _directory;
  final ErrorLogger _logger;
  final ShareLauncher _share;
  final DateTime Function() _clock;
  final Map<ExportFormat, SummaryExporter> _exporters;

  /// Genera `spendy_resumen_AAAA.ext` y lo comparte. Si algo falla, borra
  /// el archivo parcial, lo registra y devuelve un error para reintentar
  /// (RF-44). Devuelve la ruta del archivo generado.
  Future<Result<String>> export(
    AnnualSummary summary,
    ExportFormat format,
  ) async {
    File? target;
    try {
      final dir = Directory(p.join((await _directory()).path, 'exportaciones'));
      await dir.create(recursive: true);
      target = File(p.join(dir.path, exportFileName(summary.year, format)));
      final bytes = await _exporters[format]!.render(summary, _clock());
      await _writeAtomically(target, bytes);
      await _share(target, format);
      return Success(target.path);
    } on Object catch (e) {
      await _deleteQuietly(target);
      return Failure(await _failure(e));
    }
  }

  /// Escribe a un `.part` y lo renombra: nunca queda un archivo a medias.
  Future<void> _writeAtomically(File target, List<int> bytes) async {
    final partial = File('${target.path}.part');
    try {
      await partial.writeAsBytes(bytes, flush: true);
      await partial.rename(target.path);
    } on Object {
      await _deleteQuietly(partial);
      rethrow;
    }
  }

  Future<void> _deleteQuietly(File? file) async {
    try {
      if (file != null && await file.exists()) await file.delete();
    } on Object {
      // Es un archivo temporal; el sistema limpia la caché.
    }
  }

  Future<AppError> _failure(Object e) async {
    final full = isDiskFullError(e);
    await _logger.log(type: ErrorType.export, module: module, cause: e);
    return AppError(
      type: full ? ErrorType.storageFull : ErrorType.export,
      message: full ? ExportMessages.storageFull : ExportMessages.failed,
    );
  }
}

/// Carpetas de la caché donde se dejan los archivos para compartir: los
/// resúmenes (M-08) y las copias de seguridad (M-16).
const List<String> sharedCopyFolders = ['exportaciones', 'respaldos'];

/// AUD-16: borra los resúmenes y copias que se generaron para compartir en
/// sesiones anteriores. Se llama al abrir la app, cuando ya nadie está
/// leyendo esos archivos. Nunca falla: es limpieza.
Future<void> cleanSharedCopies(Directory cache) async {
  for (final name in sharedCopyFolders) {
    try {
      final dir = Directory(p.join(cache.path, name));
      if (await dir.exists()) await dir.delete(recursive: true);
    } on Object {
      // La caché se limpiará en otro arranque o la limpia el sistema.
    }
  }
}
