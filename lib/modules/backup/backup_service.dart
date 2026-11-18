/// M-16 · Copia de seguridad: exporta todos los movimientos, recibos y
/// presupuestos a un archivo cifrado `.spendy` y lo restaura en este u
/// otro teléfono.
///
/// Los datos siguen siendo solo de la persona (TEC-02): el archivo se
/// cifra con su contraseña y se entrega al menú de compartir para que
/// elija dónde guardarlo; la app no lo sube a ningún lado.
///
/// La restauración reemplaza todo en un solo paso: primero escribe las
/// fotos con nombres nuevos, luego cambia las filas en una transacción y
/// al final borra las fotos viejas. Si algo falla a medias, los datos
/// anteriores quedan intactos y las fotos sueltas se limpian al iniciar.
library;

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/error_logger.dart';
import '../../core/result.dart';
import '../../data/database.dart';
import '../../data/image_store.dart';
import 'backup_codec.dart';

export 'backup_codec.dart' show BackupCodec;

/// Mensajes de la copia de seguridad (RNF-05).
class BackupMessages {
  BackupMessages._();

  static const String shortPassword =
      'La contraseña debe tener al menos 8 caracteres.';
  static const String exportFailed =
      'No se pudo crear la copia de seguridad. Revisa que el teléfono tenga '
      'espacio libre e inténtalo de nuevo.';
  static const String notBackup =
      'Ese archivo no es una copia de seguridad de SPENDY. Elige un archivo '
      'que termine en .spendy.';
  static const String wrongPassword =
      'La contraseña no es correcta. Escríbela de nuevo; distingue '
      'mayúsculas y minúsculas.';
  static const String corrupted =
      'La copia de seguridad está dañada y no se puede restaurar. Tus datos '
      'actuales no cambiaron.';
  static const String newerVersion =
      'Esta copia se hizo con una versión más nueva de SPENDY. Actualiza la '
      'app y vuelve a intentarlo.';
  static const String restoreFailed =
      'No se pudo restaurar la copia. Tus datos actuales no cambiaron; '
      'inténtalo de nuevo.';
}

/// Cuántos registros trae una copia restaurada.
class RestoreSummary {
  const RestoreSummary({
    required this.movements,
    required this.receipts,
    required this.budgets,
  });

  final int movements;
  final int receipts;
  final int budgets;
}

/// Entrega el archivo al menú de compartir o guardar del sistema.
typedef BackupShare = Future<void> Function(File file);

Future<void> shareBackup(File file) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'application/octet-stream')],
      fileNameOverrides: [p.basename(file.path)],
    ),
  );
}

/// Orquesta exportar y restaurar.
class BackupService {
  BackupService({
    required Database db,
    required ImageStore images,
    required Future<Directory> Function() directory,
    required ErrorLogger logger,
    BackupCodec? codec,
    BackupShare share = shareBackup,
    DateTime Function()? clock,
  })  : _db = db,
        _images = images,
        _directory = directory,
        _logger = logger,
        _codec = codec ?? BackupCodec(),
        _share = share,
        _clock = clock ?? DateTime.now;

  static const String module = 'M-16';
  static const String app = 'spendy';

  /// Formato de `respaldo.json`. Sube si cambia su estructura.
  static const int dataVersion = 1;

  /// Nombre de un recibo dentro del respaldo: solo letras, números, `_`,
  /// `-` y `.jpg`. Evita que un archivo manipulado escriba fuera de la
  /// carpeta de recibos (`../`).
  static final RegExp safeImageName = RegExp(r'^[A-Za-z0-9_\-]{1,80}\.jpg$');

  final Database _db;
  final ImageStore _images;
  final Future<Directory> Function() _directory;
  final ErrorLogger _logger;
  final BackupCodec _codec;
  final BackupShare _share;
  final DateTime Function() _clock;

  /// `spendy_respaldo_AAAA-MM-DD.spendy`.
  String fileName() {
    final d = _clock();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'spendy_respaldo_${d.year}-${two(d.month)}-${two(d.day)}.spendy';
  }

  /// Crea el respaldo cifrado con [password] y lo comparte. Devuelve la
  /// ruta del archivo.
  Future<Result<String>> export(String password) async {
    if (password.length < BackupCodec.minPasswordLength) {
      return const Failure(AppError(
          type: ErrorType.validation, message: BackupMessages.shortPassword));
    }
    File? target;
    try {
      final payload = await _collect();
      // PBKDF2 tarda: se corre en otro isolate para no congelar la pantalla.
      final iterations = _codec.iterations;
      final bytes = await Isolate.run(
          () => BackupCodec(iterations: iterations).encode(payload, password));
      final dir = Directory(p.join((await _directory()).path, 'respaldos'));
      await dir.create(recursive: true);
      target = File(p.join(dir.path, fileName()));
      final partial = File('${target.path}.part');
      await partial.writeAsBytes(bytes, flush: true);
      await partial.rename(target.path);
      await _share(target);
      return Success(target.path);
    } on Object catch (e) {
      if (target != null) await _images.deleteQuietly(target);
      final full = isDiskFullError(e);
      await _logger.log(
          type: full ? ErrorType.storageFull : ErrorType.export,
          module: module,
          cause: e);
      return const Failure(
        AppError(type: ErrorType.export, message: BackupMessages.exportFailed),
      );
    }
  }

  Future<BackupPayload> _collect() async {
    final movements = await _db.query('movimiento', orderBy: 'id');
    final receipts = await _db.query('recibo', orderBy: 'id');
    final budgets = await _db.query('presupuesto');
    final images = <String, Uint8List>{};
    final receiptRows = <Map<String, Object?>>[];
    for (final row in receipts) {
      final file = _images.resolve(row['ruta_archivo'] as String);
      if (!await file.exists()) continue; // foto perdida: no se respalda
      final name = p.basename(file.path);
      images[name] = await file.readAsBytes();
      receiptRows.add({...row, 'archivo': name});
    }
    return BackupPayload(
      data: {
        'app': app,
        'formato': dataVersion,
        'esquema': schemaVersion,
        'creado_en': _clock().toIso8601String(),
        'movimientos': movements,
        'recibos': receiptRows,
        'presupuestos': budgets,
      },
      images: images,
    );
  }

  /// Reemplaza todos los datos por los de [bytes] (un archivo `.spendy`).
  Future<Result<RestoreSummary>> restore(
    Uint8List bytes,
    String password,
  ) async {
    final BackupPayload payload;
    try {
      final iterations = _codec.iterations;
      payload = await Isolate.run(
          () => BackupCodec(iterations: iterations).decode(bytes, password));
    } on BackupFormatException catch (e) {
      return _invalid(switch (e.error) {
        BackupError.notBackup => BackupMessages.notBackup,
        BackupError.wrongPassword => BackupMessages.wrongPassword,
        BackupError.corrupted => BackupMessages.corrupted,
      });
    }
    final data = payload.data;
    if (data['app'] != app || data['formato'] is! int) {
      return _invalid(BackupMessages.notBackup);
    }
    if ((data['formato'] as int) > dataVersion) {
      return _invalid(BackupMessages.newerVersion);
    }
    final _RestoreRows rows;
    try {
      rows = _RestoreRows.parse(data, payload.images);
    } on Object {
      return _invalid(BackupMessages.corrupted);
    }
    return _apply(rows, payload.images);
  }

  static Failure<RestoreSummary> _invalid(String message) =>
      Failure(AppError(type: ErrorType.validation, message: message));

  /// Escribe las fotos con nombres nuevos y cambia las filas en una
  /// transacción. Si algo falla borra lo que escribió y no toca la base.
  Future<Result<RestoreSummary>> _apply(
    _RestoreRows rows,
    Map<String, Uint8List> images,
  ) async {
    final written = <File>[];
    try {
      final receiptRows = await _writeImages(rows.receipts, images, written);
      await _db.transaction((txn) async {
        for (final table in ['recibo', 'presupuesto', 'movimiento']) {
          await txn.delete(table);
        }
        for (final (table, list) in [
          ('movimiento', rows.movements),
          ('recibo', receiptRows),
          ('presupuesto', rows.budgets),
        ]) {
          for (final row in list) {
            await txn.insert(table, row);
          }
        }
      });
      // Las fotos que ya no están en la tabla (las de antes) se borran.
      final paths = await _db.query('recibo', columns: ['ruta_archivo']);
      await _images.cleanOrphanImages(
          {for (final row in paths) row['ruta_archivo'] as String});
      return Success(RestoreSummary(
        movements: rows.movements.length,
        receipts: receiptRows.length,
        budgets: rows.budgets.length,
      ));
    } on Object catch (e) {
      for (final file in written) {
        await _images.deleteQuietly(file);
      }
      return Failure(await _restoreFailure(e));
    }
  }

  Future<List<Map<String, Object?>>> _writeImages(
    List<Map<String, Object?>> receipts,
    Map<String, Uint8List> images,
    List<File> written,
  ) async {
    await _images.init();
    final stamp = _clock().millisecondsSinceEpoch;
    final rows = <Map<String, Object?>>[];
    for (var i = 0; i < receipts.length; i++) {
      final r = receipts[i];
      final image = images[r['archivo']]!;
      await _images.ensureSpace(image.length);
      final relative = p.join(receiptsFolder, 'rest_${stamp}_$i.jpg');
      final file = _images.resolve(relative);
      await file.writeAsBytes(image, flush: true);
      written.add(file);
      rows.add({
        'id': r['id'] as int,
        'movimiento_id': r['movimiento_id'] as int,
        'ruta_archivo': relative,
        'tamano_bytes': image.length,
        'capturado_en': r['capturado_en'] as String,
      });
    }
    return rows;
  }

  Future<AppError> _restoreFailure(Object e) async {
    final error = translateStorageError(e, writing: true);
    await _logger.log(type: error.type, module: module, cause: e);
    return AppError(
      type: error.type,
      message: error.type == ErrorType.storageFull
          ? error.message
          : BackupMessages.restoreFailed,
    );
  }
}

/// Filas de un respaldo ya revisadas: tipos correctos y cada recibo con una
/// foto de nombre seguro. Lanza si algo no cuadra.
class _RestoreRows {
  _RestoreRows(this.movements, this.receipts, this.budgets);

  factory _RestoreRows.parse(
    Map<String, Object?> data,
    Map<String, Uint8List> images,
  ) {
    final receipts = _rows(data['recibos']);
    for (final r in receipts) {
      final name = r['archivo'];
      if (name is! String ||
          !BackupService.safeImageName.hasMatch(name) ||
          !images.containsKey(name)) {
        throw const FormatException('recibo sin foto válida');
      }
    }
    return _RestoreRows(
      _rows(data['movimientos']).map(_movementRow).toList(),
      receipts,
      _rows(data['presupuestos']).map(_budgetRow).toList(),
    );
  }

  final List<Map<String, Object?>> movements;
  final List<Map<String, Object?>> receipts;
  final List<Map<String, Object?>> budgets;
  static List<Map<String, Object?>> _rows(Object? value) => value == null
      ? const []
      : [for (final row in value as List) (row as Map).cast<String, Object?>()];

  static final RegExp _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  /// Revisa y copia solo las columnas conocidas de un movimiento.
  static Map<String, Object?> _movementRow(Map<String, Object?> r) {
    final tipo = r['tipo'];
    final monto = r['monto_centavos'];
    final fecha = r['fecha'];
    if ((tipo != 'ingreso' && tipo != 'egreso') ||
        monto is! int ||
        monto <= 0 ||
        fecha is! String ||
        !_isoDate.hasMatch(fecha)) {
      throw const FormatException('movimiento inválido');
    }
    return {
      'id': r['id'] as int,
      'tipo': tipo,
      'monto_centavos': monto,
      'fecha': fecha,
      'categoria_id': r['categoria_id'] as int,
      'metodo_pago': r['metodo_pago'] as String?,
      'descripcion': r['descripcion'] as String?,
      'nota': r['nota'] as String?,
      'creado_en': r['creado_en'] as String,
      'actualizado_en': r['actualizado_en'] as String,
    };
  }

  static Map<String, Object?> _budgetRow(Map<String, Object?> r) => {
        'categoria_id': r['categoria_id'] as int,
        'monto_centavos': r['monto_centavos'] as int,
        'actualizado_en': r['actualizado_en'] as String,
      };
}
