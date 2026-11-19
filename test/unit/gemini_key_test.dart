// Pruebas de la respuesta estructurada de Gemini y de la clave capturada
// en Ajustes (TEC-01: la clave nunca va dentro del APK).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:spendy/core/error_logger.dart';
import 'package:spendy/core/result.dart';
import 'package:spendy/data/secure_store.dart';
import 'package:spendy/modules/ocr/cloud_ocr_adapter.dart';
import 'package:spendy/modules/ocr/gemini_ocr_adapter.dart';
import 'package:spendy/modules/ocr/ocr_adapter.dart';
import 'package:spendy/modules/ocr/ocr_key_service.dart';
import 'package:spendy/modules/ocr/receipt_parser.dart';

final Uint8List image = Uint8List.fromList([0xFF, 0xD8, 1, 2, 3]);
const String validKey = 'AIzaSyA-1234567890abcdefghijklmnopqrstuv';

String geminiBody(String text) => jsonEncode({
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': text},
            ],
          },
        },
      ],
    });

class _FakeAdapter implements OcrAdapter {
  int calls = 0;

  @override
  Future<String> recognize(Uint8List image, OcrCancelToken cancel) async {
    calls++;
    return 'ML KIT';
  }
}

void main() {
  group('receiptJsonToText', () {
    test('arma renglones que entiende el intérprete', () {
      final text = receiptJsonToText(jsonEncode({
        'legible': true,
        'comercio': '  OXXO   Tienda 1234 ',
        'fecha': '2026-11-10',
        'total': 1234.5,
      }));
      expect(text, 'OXXO Tienda 1234\nFECHA 10/11/2026\nTOTAL \$1234.50');
      final r = ReceiptParser(clock: () => DateTime(2026, 11, 18)).parse(text);
      expect(r.merchant, 'OXXO Tienda 1234');
      expect(r.date, DateTime(2026, 11, 10));
      expect(r.amountText, '1234.50');
      expect(r.missing, isEmpty);
    });

    test('ilegible o vacío da texto vacío (RF-29)', () {
      expect(receiptJsonToText('{"legible": false, "total": 10}'), '');
      expect(receiptJsonToText('{"legible": true}'), '');
      expect(
        ReceiptParser()
            .parse(receiptJsonToText('{"legible": false}'))
            .illegible,
        isTrue,
      );
    });

    test('omite lo que falta y deja pasar texto que no es JSON', () {
      expect(receiptJsonToText('{"legible": true, "total": 39.5}'),
          'TOTAL \$39.50');
      expect(receiptJsonToText('{"legible": true, "fecha": "10/11/2026"}'), '',
          reason: 'fecha sin formato AAAA-MM-DD se descarta');
      expect(receiptJsonToText('OXXO\nTOTAL 1.00'), 'OXXO\nTOTAL 1.00');
    });

    test('la petición pide JSON con esquema fijo', () {
      final body = jsonDecode(utf8.decode(buildGeminiRequest(image)));
      final config = body['generationConfig'] as Map;
      expect(config['responseMimeType'], 'application/json');
      expect(config['responseSchema'], geminiReceiptSchema);
    });
  });

  group('KeyedGeminiOcrAdapter', () {
    test('sin clave usa el respaldo en el teléfono', () async {
      final fallback = _FakeAdapter();
      final adapter = KeyedGeminiOcrAdapter(
        readKey: () async => null,
        fallback: fallback,
        transport: (_, __, ___, ____) => fail('no debe usar la red'),
      );
      expect(await adapter.recognize(image, OcrCancelToken()), 'ML KIT');
      expect(fallback.calls, 1);
    });

    test('con clave usa Gemini con esa clave en el encabezado', () async {
      final fallback = _FakeAdapter();
      String? seenKey;
      final adapter = KeyedGeminiOcrAdapter(
        readKey: () async => validKey,
        fallback: fallback,
        transport: (uri, headers, _, __) async {
          seenKey = headers['x-goog-api-key'];
          return OcrHttpResponse(
              200, geminiBody('{"legible":true,"total":10}'));
        },
      );
      expect(await adapter.recognize(image, OcrCancelToken()), 'TOTAL \$10.00');
      expect(seenKey, validKey);
      expect(fallback.calls, 0);
    });
  });

  group('OcrKeyService', () {
    late Directory dir;
    late MemorySecureBackend backend;
    late OcrKeyService service;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('spendy_key_');
      backend = MemorySecureBackend();
      service = OcrKeyService(
        SecureStore(backend),
        ErrorLogger(() async => File(p.join(dir.path, errorLogFileName))),
      );
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('guarda la clave sin espacios y muestra solo el final', () async {
      expect((await service.save('  $validKey \n')).isSuccess, isTrue);
      expect(backend.values[SecureStore.geminiApiKeyKey], validKey);
      expect(await service.read(), validKey);
      final status = await service.status();
      expect(status.configured, isTrue);
      expect(status.lastChars, 'stuv');
    });

    test('rechaza texto que no parece clave', () async {
      for (final bad in ['', 'corta', 'con espacios en medio de la clave xx']) {
        final r = await service.save(bad);
        expect(r, isA<Failure<void>>());
        expect(r.errorOrNull!.message, OcrKeyMessages.invalid);
      }
      expect(backend.values, isEmpty);
    });

    test('quitar la clave la borra del almacén seguro', () async {
      await service.save(validKey);
      await service.remove();
      expect(await service.read(), isNull);
      expect((await service.status()).configured, isFalse);
    });

    test('desactivar el PIN no borra la clave', () async {
      await service.save(validKey);
      await SecureStore(backend).clearSecurity();
      expect(await service.read(), validKey);
    });

    test('si falla la escritura avisa sin romper', () async {
      backend.failWrites = true;
      final r = await service.save(validKey);
      expect(r.errorOrNull!.message, OcrKeyMessages.saveFailed);
    });
  });

  group('Clave del equipo compilada en el APK', () {
    test('la clave compilada se usa sin variables de entorno', () {
      final config = GeminiOcrConfig.fromEnvironment(
        environment: const {},
        compiledKey: validKey,
      );
      expect(config, isNotNull);
      expect(config!.apiKey, validKey);
      expect(config.models, GeminiEnvironment.defaultModels);
    });

    test('la clave compilada gana sobre la del entorno', () {
      final config = GeminiOcrConfig.fromEnvironment(
        environment: const {
          GeminiEnvironment.apiKeyKey: 'otra-clave-123456789012'
        },
        compiledKey: validKey,
      );
      expect(config!.apiKey, validKey);
    });

    test('sin clave compilada ni de entorno no hay Gemini', () {
      expect(
        GeminiOcrConfig.fromEnvironment(environment: const {}, compiledKey: ''),
        isNull,
      );
    });
  });
}
