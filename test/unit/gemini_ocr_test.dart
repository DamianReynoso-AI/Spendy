// Pruebas del OCR con la API de Gemini (M-05; RNF-16 a RNF-18, RNF-32):
// petición (solo HTTPS, clave en encabezado, solo la imagen), lectura de la
// respuesta y errores.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:spendy/modules/ocr/cloud_ocr_adapter.dart';
import 'package:spendy/modules/ocr/gemini_ocr_adapter.dart';
import 'package:spendy/modules/ocr/ocr_adapter.dart';
import 'package:spendy/modules/ocr/receipt_parser.dart';

final Uint8List image = Uint8List.fromList([0xFF, 0xD8, 1, 2, 3]);

String geminiBody(String text) => jsonEncode({
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': text},
            ],
            'role': 'model',
          },
        },
      ],
    });

void main() {
  group('GeminiOcrConfig', () {
    test('sin clave no hay configuración', () {
      expect(GeminiOcrConfig.fromEnvironment(environment: {}), isNull);
      expect(
        GeminiOcrConfig.fromEnvironment(
            environment: {GeminiEnvironment.apiKeyKey: '  '}),
        isNull,
      );
    });

    test('lee clave y modelo; el modelo por omisión es Flash', () {
      final c = GeminiOcrConfig.fromEnvironment(
          environment: {GeminiEnvironment.apiKeyKey: ' abc '})!;
      expect(c.apiKey, 'abc');
      expect(c.models, GeminiEnvironment.defaultModels);
      final d = GeminiOcrConfig.fromEnvironment(environment: {
        GeminiEnvironment.apiKeyKey: 'abc',
        GeminiEnvironment.modelKey: ' modelo-a , modelo-b ',
      })!;
      expect(d.models, ['modelo-a', 'modelo-b']);
    });

    test('RNF-16: el endpoint siempre es HTTPS de Google', () {
      final e = GeminiOcrConfig(apiKey: 'k').endpointFor('m');
      expect(e.scheme, 'https');
      expect(e.host, 'generativelanguage.googleapis.com');
      expect(e.path, '/v1beta/models/m:generateContent');
      expect(e.query, isEmpty, reason: 'la clave no va en la URL');
    });
  });

  group('GeminiOcrAdapter', () {
    test('envía la clave en encabezado y solo la imagen con la instrucción',
        () async {
      late Uri seenUri;
      late Map<String, String> seenHeaders;
      late Map<String, dynamic> seenBody;
      final adapter = GeminiOcrAdapter(
        GeminiOcrConfig(apiKey: 'secreta'),
        transport: (uri, headers, body, cancel) async {
          seenUri = uri;
          seenHeaders = headers;
          seenBody = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
          return OcrHttpResponse(200, geminiBody('OXXO\nTOTAL \$39.50'));
        },
      );
      final text = await adapter.recognize(image, OcrCancelToken());
      expect(text, 'OXXO\nTOTAL \$39.50');
      expect(seenUri.scheme, 'https');
      expect(seenHeaders['x-goog-api-key'], 'secreta');
      expect(seenUri.toString(), isNot(contains('secreta')));
      final parts = seenBody['contents'][0]['parts'] as List;
      expect(parts, hasLength(2));
      expect(parts[0]['text'], geminiReceiptPrompt);
      expect(parts[1]['inline_data']['mime_type'], 'image/jpeg');
      expect(base64Decode(parts[1]['inline_data']['data'] as String), image);
    });

    test('el texto de Gemini lo entiende el intérprete de recibos', () async {
      final adapter = GeminiOcrAdapter(
        GeminiOcrConfig(apiKey: 'k'),
        transport: (_, __, ___, ____) async => OcrHttpResponse(
          200,
          geminiBody('OXXO TIENDA 1234\nFECHA: 10/11/2026\n'
              'SUBTOTAL 34.05\nTOTAL \$39.50\nEFECTIVO 100.00'),
        ),
      );
      final text = await adapter.recognize(image, OcrCancelToken());
      final r = ReceiptParser(clock: () => DateTime(2026, 11, 18)).parse(text);
      expect(r.merchant, 'OXXO TIENDA 1234');
      expect(r.date, DateTime(2026, 11, 10));
      expect(r.amountText, '39.50');
    });

    test('si un modelo está saturado o sin cuota, prueba el siguiente',
        () async {
      final seen = <String>[];
      final adapter = GeminiOcrAdapter(
        GeminiOcrConfig(apiKey: 'k', model: 'a,b,c'),
        transport: (uri, _, __, ___) async {
          seen.add(uri.pathSegments.last);
          return switch (seen.length) {
            1 => const OcrHttpResponse(503, '{}'),
            2 => const OcrHttpResponse(429, '{}'),
            _ => OcrHttpResponse(200, geminiBody('OXXO')),
          };
        },
      );
      expect(await adapter.recognize(image, OcrCancelToken()), 'OXXO');
      expect(seen,
          ['a:generateContent', 'b:generateContent', 'c:generateContent']);
    });

    test('una clave inválida no prueba otros modelos', () async {
      var calls = 0;
      final adapter = GeminiOcrAdapter(
        GeminiOcrConfig(apiKey: 'k', model: 'a,b'),
        transport: (_, __, ___, ____) async {
          calls++;
          return const OcrHttpResponse(400, '{}');
        },
      );
      await expectLater(adapter.recognize(image, OcrCancelToken()),
          throwsA(isA<OcrException>()));
      expect(calls, 1);
    });

    test('sin conexión se reporta como noConnection', () async {
      final adapter = GeminiOcrAdapter(
        GeminiOcrConfig(apiKey: 'k'),
        transport: (_, __, ___, ____) async =>
            throw const SocketExceptionLike(),
      );
      await expectLater(
        adapter.recognize(image, OcrCancelToken()),
        throwsA(isA<OcrException>()
            .having((e) => e.kind, 'kind', OcrFailureKind.noConnection)),
      );
    });
  });

  group('parseGeminiResponse', () {
    test('junta varias partes de texto', () {
      final body = jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'OXXO\n'},
                {'text': 'TOTAL 1.00\n'},
              ],
            },
          },
        ],
      });
      expect(
          parseGeminiResponse(OcrHttpResponse(200, body)), 'OXXO\nTOTAL 1.00');
    });

    test('respuesta bloqueada sin partes devuelve texto vacío', () {
      final body = jsonEncode({
        'candidates': [
          {'finishReason': 'SAFETY'},
        ],
      });
      expect(parseGeminiResponse(OcrHttpResponse(200, body)), '');
    });

    test('clave inválida: error del servicio con el código en el detalle', () {
      final body = jsonEncode({
        'error': {
          'code': 400,
          'message': 'API key not valid.',
          'status': 'INVALID_ARGUMENT',
        },
      });
      expect(
        () => parseGeminiResponse(OcrHttpResponse(400, body)),
        throwsA(isA<OcrException>()
            .having((e) => e.kind, 'kind', OcrFailureKind.server)
            .having((e) => e.detail, 'detail',
                'HTTP 400 INVALID_ARGUMENT: API key not valid.')),
      );
    });

    test('cuerpo que no es JSON o sin candidatos es error del servicio', () {
      for (final body in ['<html>', '{}', '{"candidates":[]}']) {
        expect(
          () => parseGeminiResponse(OcrHttpResponse(200, body)),
          throwsA(isA<OcrException>()
              .having((e) => e.kind, 'kind', OcrFailureKind.server)),
        );
      }
    });
  });
}

/// Error cualquiera del transporte (como un SocketException).
class SocketExceptionLike implements Exception {
  const SocketExceptionLike();
}
