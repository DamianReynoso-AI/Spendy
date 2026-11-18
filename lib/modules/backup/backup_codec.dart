/// M-16 · Formato del archivo de respaldo `.spendy`: un ZIP con
/// `respaldo.json` y las fotos de los recibos, cifrado con AES-256-GCM y
/// una clave derivada de la contraseña con PBKDF2-HMAC-SHA256 (TEC-02).
///
/// ```text
/// "SPENDYBK" (8) | versión (1) | sal (16) | nonce (12) | cifrado | MAC (16)
/// ```
///
/// Sin la contraseña el archivo no se puede leer, y cualquier cambio en
/// sus bytes hace fallar la verificación (MAC) antes de restaurar nada.
///
/// Lógica pura: no usa Flutter, la base ni archivos.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';

/// Contenido de un respaldo ya descifrado.
class BackupPayload {
  const BackupPayload({required this.data, required this.images});

  /// El JSON de `respaldo.json`.
  final Map<String, Object?> data;

  /// Fotos de los recibos: nombre del archivo -> bytes.
  final Map<String, Uint8List> images;
}

/// Por qué no se pudo abrir un respaldo.
enum BackupError { notBackup, wrongPassword, corrupted }

class BackupFormatException implements Exception {
  const BackupFormatException(this.error);
  final BackupError error;

  @override
  String toString() => 'BackupFormatException: ${error.name}';
}

/// Cifra y descifra respaldos.
class BackupCodec {
  BackupCodec({this.iterations = defaultIterations});

  static const List<int> magic = [
    0x53,
    0x50,
    0x45,
    0x4E,
    0x44,
    0x59,
    0x42,
    0x4B
  ];
  static const int formatVersion = 1;
  static const int defaultIterations = 120000;
  static const int minPasswordLength = 8;
  static const String jsonName = 'respaldo.json';
  static const String imagesFolder = 'recibos/';

  static const int _saltBytes = 16;
  static const int _nonceBytes = 12;
  static const int _macBytes = 16;
  static const int _headerBytes = 8 + 1 + _saltBytes + _nonceBytes;

  /// Iteraciones de PBKDF2. Las pruebas usan menos para ir rápido.
  final int iterations;

  final AesGcm _aes = AesGcm.with256bits();

  Future<SecretKey> _key(String password, List<int> salt) =>
      Pbkdf2.hmacSha256(iterations: iterations, bits: 256)
          .deriveKeyFromPassword(
        password: password,
        nonce: salt,
      );

  /// Empaca y cifra [payload] con [password].
  Future<Uint8List> encode(BackupPayload payload, String password) async {
    final archive = Archive();
    final json = utf8.encode(jsonEncode(payload.data));
    archive.addFile(ArchiveFile(jsonName, json.length, json));
    for (final entry in payload.images.entries) {
      archive.addFile(ArchiveFile.noCompress(
        '$imagesFolder${entry.key}',
        entry.value.length,
        entry.value,
      ));
    }
    final zip = ZipEncoder().encode(archive);
    final salt = SecretKeyData.random(length: _saltBytes).bytes;
    final nonce = _aes.newNonce();
    final box = await _aes.encrypt(
      zip,
      secretKey: await _key(password, salt),
      nonce: nonce,
    );
    return Uint8List.fromList([
      ...magic,
      formatVersion,
      ...salt,
      ...box.nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  /// Descifra y desempaca. Lanza [BackupFormatException].
  Future<BackupPayload> decode(Uint8List bytes, String password) async {
    if (bytes.length < _headerBytes + _macBytes ||
        !_startsWithMagic(bytes) ||
        bytes[8] != formatVersion) {
      throw const BackupFormatException(BackupError.notBackup);
    }
    final salt = bytes.sublist(9, 9 + _saltBytes);
    final nonce = bytes.sublist(9 + _saltBytes, _headerBytes);
    final cipher = bytes.sublist(_headerBytes, bytes.length - _macBytes);
    final mac = Mac(bytes.sublist(bytes.length - _macBytes));
    final List<int> zip;
    try {
      zip = await _aes.decrypt(
        SecretBox(cipher, nonce: nonce, mac: mac),
        secretKey: await _key(password, salt),
      );
    } on SecretBoxAuthenticationError {
      throw const BackupFormatException(BackupError.wrongPassword);
    }
    try {
      final archive = ZipDecoder().decodeBytes(zip);
      Map<String, Object?>? data;
      final images = <String, Uint8List>{};
      for (final file in archive.files) {
        if (!file.isFile) continue;
        final content = Uint8List.fromList(file.content as List<int>);
        if (file.name == jsonName) {
          data = (jsonDecode(utf8.decode(content)) as Map).cast();
        } else if (file.name.startsWith(imagesFolder)) {
          images[file.name.substring(imagesFolder.length)] = content;
        }
      }
      if (data == null) throw const FormatException('sin respaldo.json');
      return BackupPayload(data: data, images: images);
    } on BackupFormatException {
      rethrow;
    } on Object {
      throw const BackupFormatException(BackupError.corrupted);
    }
  }

  static bool _startsWithMagic(Uint8List bytes) {
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    return true;
  }
}
