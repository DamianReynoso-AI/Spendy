/// M-11 · Imágenes de recibos en el almacenamiento privado de la app
/// (RF-22; RNF-14, RNF-21; TEC-06; CA-052, CA-059 a CA-061).
///
/// Todas las imágenes viven dentro de la carpeta privada de la app, en dos
/// subcarpetas:
/// - `temp_recibos/`: capturas que aún no se guardan con un egreso.
/// - `recibos/`: recibos ya vinculados a un egreso en la tabla `recibo`.
///
/// Cada subcarpeta tiene un archivo `.nomedia` para que Android no las
/// indexe en la galería. La carpeta privada (Application Support) tampoco
/// la ve la app Fotos de iOS (RNF-14, CA-052).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../config/app_config.dart';

/// Subcarpeta de capturas temporales.
const String tempReceiptsFolder = 'temp_recibos';

/// Subcarpeta de recibos definitivos.
const String receiptsFolder = 'recibos';

/// Archivo que le indica a Android que no muestre la carpeta en la galería.
const String noMediaFileName = '.nomedia';

/// No hay espacio libre suficiente para escribir la imagen (RF-22).
/// Su `toString` contiene "no space left" para que M-13 lo traduzca al
/// mensaje de almacenamiento lleno.
class InsufficientSpaceException implements Exception {
  const InsufficientSpaceException(this.requiredBytes, this.freeBytes);

  final int requiredBytes;
  final int freeBytes;

  @override
  String toString() => 'InsufficientSpaceException: no space left on device';
}

/// Devuelve los bytes libres del sistema de archivos de [directory], o
/// `null` si no se pueden saber (entonces no se bloquea la escritura y se
/// confía en que el sistema avise con ENOSPC).
typedef FreeSpaceProbe = Future<int?> Function(String directory);

/// Lee el espacio libre con `df -k`, disponible en Android (toybox), iOS y
/// Linux. Si el comando no existe o su salida no se entiende, `null`.
Future<int?> systemFreeSpace(String directory) async {
  try {
    final result = await Process.run('df', ['-k', directory]);
    if (result.exitCode != 0) return null;
    return parseDfAvailableBytes(result.stdout.toString());
  } on Object {
    return null;
  }
}

/// Extrae la columna "Available" (en KB) de la salida de `df -k`.
int? parseDfAvailableBytes(String output) {
  final lines =
      output.trim().split('\n').where((l) => l.trim().isNotEmpty).toList();
  if (lines.length < 2) return null;
  final columns = lines.last.trim().split(RegExp(r'\s+'));
  if (columns.length < 4) return null;
  final kb = int.tryParse(columns[3]);
  return kb == null ? null : kb * 1024;
}

/// Manejo de los archivos de imagen de los recibos.
class ImageStore {
  ImageStore(
    this.root, {
    FreeSpaceProbe? freeSpace,
    DateTime Function()? clock,
  })  : _freeSpace = freeSpace ?? systemFreeSpace,
        _clock = clock ?? DateTime.now;

  /// Carpeta privada de la app (Application Support).
  final Directory root;
  final FreeSpaceProbe _freeSpace;
  final DateTime Function() _clock;
  int _sequence = 0;

  Directory get tempDir => Directory(p.join(root.path, tempReceiptsFolder));
  Directory get receiptsDir => Directory(p.join(root.path, receiptsFolder));

  /// Crea las dos subcarpetas y su `.nomedia` (CA-052).
  Future<void> init() async {
    for (final dir in [tempDir, receiptsDir]) {
      await dir.create(recursive: true);
      final noMedia = File(p.join(dir.path, noMediaFileName));
      if (!await noMedia.exists()) await noMedia.writeAsBytes(const []);
    }
  }

  /// Ruta absoluta de una ruta guardada en la tabla `recibo`.
  File resolve(String relativePath) =>
      File(p.join(root.path, p.normalize(relativePath)));

  /// Ruta relativa (la que se guarda en la base) de un archivo de
  /// `recibos/`.
  String relativePathOf(File file) => p.relative(file.path, from: root.path);

  /// Escribe [bytes] como una captura nueva en `temp_recibos/`. Revisa
  /// antes el espacio libre y escribe primero a un `.part` que luego se
  /// renombra: si algo falla no queda un archivo a medias (CA-059, CA-060).
  Future<File> writeTemp(Uint8List bytes) async {
    await init();
    await ensureSpace(bytes.length);
    final target = File(p.join(tempDir.path, _newName()));
    final partial = File('${target.path}.part');
    try {
      await partial.writeAsBytes(bytes, flush: true);
      return await partial.rename(target.path);
    } on Object {
      await deleteQuietly(partial);
      rethrow;
    }
  }

  /// Copia una captura de la cámara (que vive en la caché del sistema) a
  /// `temp_recibos/` y borra la original.
  Future<File> importCapture(String sourcePath) async {
    final source = File(sourcePath);
    final bytes = await source.readAsBytes();
    final copy = await writeTemp(bytes);
    await deleteQuietly(source);
    return copy;
  }

  /// Lanza [InsufficientSpaceException] si no caben [bytes] más el margen
  /// de seguridad (RF-22).
  Future<void> ensureSpace(int bytes) async {
    final free = await _freeSpace(root.path);
    final required = bytes + AppConfig.freeSpaceMarginBytes;
    if (free != null && free < required) {
      throw InsufficientSpaceException(required, free);
    }
  }

  /// Ruta relativa que tendrá [temp] al pasar a `recibos/`.
  String finalPathFor(File temp) =>
      p.join(receiptsFolder, p.basename(temp.path));

  /// Mueve [temp] a `recibos/` (paso 3 del guardado atómico). Es un
  /// `rename` dentro del mismo sistema de archivos: no se copian bytes.
  Future<File> promote(File temp) async {
    await receiptsDir.create(recursive: true);
    return temp.rename(resolve(finalPathFor(temp)).path);
  }

  /// Borra un archivo si existe; nunca lanza (limpieza en caso de fallo).
  Future<void> deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on Object {
      // Si no se puede borrar, cleanOrphanImages lo quitará al iniciar.
    }
  }

  /// Borra un recibo por su ruta relativa (RF-09, RF-20).
  Future<void> deleteRelative(String relativePath) =>
      deleteQuietly(resolve(relativePath));

  /// Al iniciar la app: borra todo `temp_recibos/` y cada archivo de
  /// `recibos/` que no esté en [registeredPaths] (rutas de la tabla
  /// `recibo`). Devuelve cuántos archivos borró (TEC-06, RNF-21).
  Future<int> cleanOrphanImages(Set<String> registeredPaths) async {
    await init();
    final registered = registeredPaths.map(p.normalize).toSet();
    var removed = 0;
    removed += await _deleteWhere(tempDir, (_) => true);
    removed += await _deleteWhere(
      receiptsDir,
      (file) => !registered.contains(p.normalize(relativePathOf(file))),
    );
    return removed;
  }

  Future<int> _deleteWhere(Directory dir, bool Function(File) test) async {
    var removed = 0;
    await for (final entity in dir.list()) {
      if (entity is! File || p.basename(entity.path) == noMediaFileName) {
        continue;
      }
      if (!test(entity)) continue;
      await deleteQuietly(entity);
      removed++;
    }
    return removed;
  }

  /// Nombre único: milisegundos más un consecutivo, sin datos del usuario.
  String _newName() => '${_clock().millisecondsSinceEpoch}_${_sequence++}.jpg';
}
