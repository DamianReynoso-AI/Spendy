// Pruebas del incremento 3 para M-11: ImageStore (almacenamiento privado,
// .nomedia, espacio libre, escritura sin archivos a medias y limpieza de
// huérfanos). CA-052, CA-059, CA-060; RNF-14, RNF-21; TEC-06.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:spendy/core/error_logger.dart';
import 'package:spendy/core/result.dart';
import 'package:spendy/data/image_store.dart';

void main() {
  late Directory root;
  int? freeBytes;
  late ImageStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('spendy_images_');
    freeBytes = null;
    store = ImageStore(root, freeSpace: (_) async => freeBytes);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  List<String> namesIn(Directory dir) =>
      dir.listSync().map((e) => p.basename(e.path)).toList()..sort();

  test('CA-052 / RNF-14: carpetas privadas con .nomedia', () async {
    await store.init();
    for (final dir in [store.tempDir, store.receiptsDir]) {
      expect(p.isWithin(root.path, dir.path), isTrue);
      expect(File(p.join(dir.path, noMediaFileName)).existsSync(), isTrue);
    }
    expect(p.basename(store.tempDir.path), tempReceiptsFolder);
    expect(p.basename(store.receiptsDir.path), receiptsFolder);
  });

  test('writeTemp escribe en temp_recibos sin dejar .part', () async {
    final file = await store.writeTemp(Uint8List.fromList([1, 2, 3]));
    expect(file.readAsBytesSync(), [1, 2, 3]);
    expect(p.dirname(file.path), store.tempDir.path);
    expect(namesIn(store.tempDir).where((n) => n.endsWith('.part')), isEmpty);
  });

  test('cada captura tiene un nombre distinto', () async {
    final a = await store.writeTemp(Uint8List(1));
    final b = await store.writeTemp(Uint8List(1));
    expect(a.path, isNot(b.path));
  });

  test('CA-059 / CA-060: sin espacio lanza error controlado y no escribe',
      () async {
    freeBytes = 1000;
    await expectLater(
      store.writeTemp(Uint8List(10)),
      throwsA(isA<InsufficientSpaceException>()),
    );
    await store.init();
    expect(namesIn(store.tempDir), [noMediaFileName]);
  });

  test('M-13 traduce la falta de espacio al mensaje de almacenamiento lleno',
      () {
    final error = translateStorageError(
      const InsufficientSpaceException(10, 1),
      writing: true,
    );
    expect(error.type, ErrorType.storageFull);
  });

  test('con espacio suficiente sí escribe', () async {
    freeBytes = 50 * 1024 * 1024;
    final file = await store.writeTemp(Uint8List(10));
    expect(file.existsSync(), isTrue);
  });

  test('importCapture copia la foto de la cámara y borra la original',
      () async {
    final source = File(p.join(root.path, 'camara.jpg'))
      ..writeAsBytesSync([9, 9]);
    final copy = await store.importCapture(source.path);
    expect(source.existsSync(), isFalse);
    expect(copy.readAsBytesSync(), [9, 9]);
    expect(p.dirname(copy.path), store.tempDir.path);
  });

  test('promote mueve a recibos y resolve devuelve la ruta absoluta', () async {
    final temp = await store.writeTemp(Uint8List.fromList([7]));
    final relative = store.finalPathFor(temp);
    final moved = await store.promote(temp);
    expect(temp.existsSync(), isFalse);
    expect(moved.path, store.resolve(relative).path);
    expect(store.relativePathOf(moved), relative);
    expect(relative.startsWith(receiptsFolder), isTrue);
  });

  test('TEC-06: cleanOrphanImages borra temporales y recibos sin registro',
      () async {
    await store.writeTemp(Uint8List(1));
    final keep = await store.promote(await store.writeTemp(Uint8List(1)));
    final orphan = await store.promote(await store.writeTemp(Uint8List(1)));
    final removed = await store.cleanOrphanImages({
      store.relativePathOf(keep),
    });
    expect(removed, 2);
    expect(namesIn(store.tempDir), [noMediaFileName]);
    expect(keep.existsSync(), isTrue);
    expect(orphan.existsSync(), isFalse);
    expect(
      File(p.join(store.receiptsDir.path, noMediaFileName)).existsSync(),
      isTrue,
    );
  });

  test('deleteQuietly no falla si el archivo no existe', () async {
    await store.deleteQuietly(File(p.join(root.path, 'no_existe.jpg')));
    await store.deleteRelative('recibos/no_existe.jpg');
  });

  group('espacio libre con df', () {
    test('lee la columna de disponibles en KB', () {
      const output = 'Filesystem 1K-blocks Used Available Use% Mounted on\n'
          '/dev/block/dm-5 1000 400 600 40% /data\n';
      expect(parseDfAvailableBytes(output), 600 * 1024);
    });

    test('salida incompleta o rara devuelve null', () {
      expect(parseDfAvailableBytes(''), isNull);
      expect(parseDfAvailableBytes('solo una línea'), isNull);
      expect(parseDfAvailableBytes('a b c d\nx y z'), isNull);
      expect(parseDfAvailableBytes('a b c d\nx y z w'), isNull);
    });

    test('systemFreeSpace no lanza aunque la carpeta no exista', () async {
      final free = await systemFreeSpace('/carpeta/que/no/existe');
      expect(free, anyOf(isNull, isA<int>()));
    });
  });
}
