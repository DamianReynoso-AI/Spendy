/// M-09 · Derivación del hash del PIN con PBKDF2-HMAC-SHA256 y sal
/// aleatoria (RNF-15; CA-118).
library;

import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../config/app_config.dart';

/// Ejecuta un cálculo pesado. En la app va en otro isolate para no
/// congelar la pantalla; en las pruebas puede ser síncrono.
typedef HashRunner = Future<Uint8List> Function(Uint8List Function() work);

Future<Uint8List> _isolateRunner(Uint8List Function() work) =>
    Isolate.run(work);

/// Calcula y compara hashes de PIN. Nunca guarda ni registra el PIN.
class PinHasher {
  PinHasher({
    this.iterations = AppConfig.pinHashIterations,
    HashRunner? runner,
    Random? random,
  })  : _runner = runner ?? _isolateRunner,
        _random = random ?? Random.secure();

  /// Iteraciones para los PIN nuevos. Las credenciales guardan las suyas,
  /// así que cambiar este valor no invalida PIN existentes.
  final int iterations;
  final HashRunner _runner;
  final Random _random;

  /// Sal criptográfica aleatoria de [AppConfig.pinSaltBytes] bytes.
  Uint8List newSalt() => Uint8List.fromList(
        List.generate(AppConfig.pinSaltBytes, (_) => _random.nextInt(256)),
      );

  /// Hash de [pin] con [salt] e [iterations] (o las por defecto).
  Future<Uint8List> hash(String pin, List<int> salt, {int? iterations}) {
    final rounds = iterations ?? this.iterations;
    final password = Uint8List.fromList(pin.codeUnits);
    final saltBytes = Uint8List.fromList(salt);
    return _runner(() => pbkdf2Sha256(password, saltBytes, rounds));
  }
}

/// PBKDF2 (RFC 8018) con HMAC-SHA256 y una salida de 32 bytes (un bloque).
Uint8List pbkdf2Sha256(Uint8List password, Uint8List salt, int iterations) {
  final hmac = Hmac(sha256, password);
  final first = Uint8List(salt.length + 4)
    ..setAll(0, salt)
    ..setAll(salt.length, const [0, 0, 0, 1]);
  var block = Uint8List.fromList(hmac.convert(first).bytes);
  final result = Uint8List.fromList(block);
  for (var i = 1; i < iterations; i++) {
    block = Uint8List.fromList(hmac.convert(block).bytes);
    for (var j = 0; j < result.length; j++) {
      result[j] ^= block[j];
    }
  }
  return result;
}

/// Compara en tiempo constante para no filtrar cuántos bytes coinciden.
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
