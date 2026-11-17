// Pruebas del incremento 4 para M-05: OcrService (tiempo límite,
// cancelación, un solo resultado), MockOcrAdapter y CloudOcrAdapter (solo
// HTTPS, solo la imagen, clave fuera del código).
// RF-23, RF-29 a RF-31; RNF-16 a RNF-18, RNF-20, RNF-32; CA-074, CA-077 a
// CA-082, CA-145.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:spendy/config/app_config.dart';
import 'package:spendy/core/error_logger.dart';
import 'package:spendy/core/result.dart';
import 'package:spendy/modules/ocr/cloud_ocr_adapter.dart';
import 'package:spendy/modules/ocr/mock_ocr_adapter.dart';
import 'package:spendy/modules/ocr/ocr_adapter.dart';
import 'package:spendy/modules/ocr/ocr_service.dart';
import 'package:spendy/modules/ocr/receipt_parser.dart';

const String legible = 'OXXO\n10/11/2026\nTOTAL 39.50';
final Uint8List image = Uint8List.fromList([0xFF, 0xD8, 1, 2, 3]);

void main() {
  late Directory tempDir;
  late File logFile;
  late ErrorLogger logger;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('spendy_ocr_');
    logFile = File(p.join(tempDir.path, errorLogFileName));
    logger = ErrorLogger(() async => logFile);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  OcrService serviceWith(
    OcrAdapter adapter, {
    Duration timeout = AppConfig.ocrTimeout,
  }) =>
      OcrService(
        adapter: adapter,
        logger: logger,
        parser: ReceiptParser(clock: () => DateTime(2026, 11, 12)),
        timeout: timeout,
      );

  group('OcrService', () {
    test('RF-30 / RNF-26: el tiempo límite es de 10 s exactos', () {
      expect(AppConfig.ocrTimeout, const Duration(seconds: 10));
    });

    test('CA-062: lectura correcta devuelve los datos y el tiempo', () async {
      final mock = MockOcrAdapter(text: legible);
      final outcome = await serviceWith(mock).start(image).result;
      expect(outcome, isA<OcrRead>());
      final read = outcome as OcrRead;
      expect(read.receipt.amountText, '39.50');
      expect(read.elapsed, lessThan(AppConfig.ocrTargetTime));
    });

    test('RNF-17: solo se envían los bytes de la imagen', () async {
      final mock = MockOcrAdapter(text: legible);
      await serviceWith(mock).start(image).result;
      expect(mock.received.single, image);
    });

    test('CA-074: texto sin datos es imagen ilegible', () async {
      final mock = MockOcrAdapter(text: '%%%');
      expect(await serviceWith(mock).start(image).result, isA<OcrIllegible>());
    });

    test(
        'CA-077 / CA-145: sin internet da mensaje no técnico y se registra '
        'sin datos', () async {
      final mock = MockOcrAdapter(
        error: const OcrException(OcrFailureKind.noConnection),
      );
      final outcome = await serviceWith(mock).start(image).result as OcrFailed;
      expect(outcome.kind, OcrFailureKind.noConnection);
      expect(outcome.error.type, ErrorType.ocr);
      expect(outcome.error.message, OcrMessages.noConnection);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
          logFile.readAsStringSync(), contains('| ocr | M-05 | OcrException'));
    });

    test(
        'CA-078: error inesperado del proveedor cuenta como error del '
        'servicio', () async {
      final mock = MockOcrAdapter(error: StateError('500 total 39.50'));
      final outcome = await serviceWith(mock).start(image).result as OcrFailed;
      expect(outcome.kind, OcrFailureKind.server);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(logFile.readAsStringSync(), isNot(contains('39.50')));
    });

    test('CA-079: si pasa el tiempo límite termina con timeout', () async {
      final mock = MockOcrAdapter(
        text: legible,
        delay: const Duration(milliseconds: 300),
      );
      final request = serviceWith(
        mock,
        timeout: const Duration(milliseconds: 30),
      ).start(image);
      final outcome = await request.result as OcrFailed;
      expect(outcome.kind, OcrFailureKind.timeout);
      expect(outcome.error.message, OcrMessages.timeout);
      expect(request.isDone, isTrue);
    });

    test('CA-080 / CA-081: al cancelar se ignora la respuesta posterior',
        () async {
      final mock = MockOcrAdapter(
        text: legible,
        delay: const Duration(milliseconds: 100),
      );
      final request = serviceWith(mock).start(image);
      request.cancel();
      expect(await request.result, isA<OcrCancelled>());
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(await request.result, isA<OcrCancelled>());
      expect(logFile.existsSync(), isFalse, reason: 'cancelar no es error');
    });

    test(
        'CA-082: cancelar justo cuando llega la respuesta da un solo '
        'resultado', () async {
      final adapter = _ControlledAdapter();
      final request = serviceWith(adapter).start(image);
      adapter.completer.complete(legible);
      request.cancel();
      request.cancel();
      final first = await request.result;
      await Future<void>.delayed(Duration.zero);
      expect(await request.result, same(first));
      expect(adapter.token!.isCancelled, isTrue);
    });

    test('cada tipo de fallo tiene su mensaje', () {
      for (final kind in OcrFailureKind.values) {
        expect(OcrMessages.forKind(kind), isNotEmpty);
      }
      expect(OcrMessages.forKind(OcrFailureKind.server), OcrMessages.server);
      expect(
        OcrMessages.forKind(OcrFailureKind.notConfigured),
        OcrMessages.notConfigured,
      );
    });

    test('sin proveedor configurado falla con aviso claro', () async {
      final outcome = await serviceWith(const UnconfiguredOcrAdapter())
          .start(image)
          .result as OcrFailed;
      expect(outcome.kind, OcrFailureKind.notConfigured);
    });
  });

  group('OcrCancelToken', () {
    test('ejecuta callbacks una vez, también los que llegan tarde', () {
      final token = OcrCancelToken();
      var calls = 0;
      token.onCancel(() => calls++);
      token.cancel();
      token.cancel();
      token.onCancel(() => calls++);
      expect(calls, 2);
      expect(const OcrException(OcrFailureKind.timeout).toString(),
          contains('timeout'));
    });
  });

  group('CloudOcrAdapter', () {
    final https = Uri.parse('https://ocr.ejemplo.mx/v1/leer');

    test('RNF-16: rechaza endpoints que no son HTTPS', () {
      expect(
        () => CloudOcrConfig(
          endpoint: Uri.parse('http://ocr.ejemplo.mx'),
          apiKey: 'k',
        ),
        throwsArgumentError,
      );
      expect(
        () => CloudOcrConfig.fromEnvironment(environment: {
          OcrEnvironment.endpointKey: 'http://inseguro.mx',
          OcrEnvironment.apiKeyKey: 'k',
        }),
        throwsArgumentError,
      );
    });

    test('RNF-18: lee endpoint y clave de variables externas', () {
      expect(CloudOcrConfig.fromEnvironment(environment: {}), isNull);
      expect(
        CloudOcrConfig.fromEnvironment(environment: {
          OcrEnvironment.endpointKey: https.toString(),
          OcrEnvironment.apiKeyKey: '  ',
        }),
        isNull,
      );
      final config = CloudOcrConfig.fromEnvironment(environment: {
        OcrEnvironment.endpointKey: ' ${https.toString()} ',
        OcrEnvironment.apiKeyKey: 'clave-secreta',
      })!;
      expect(config.endpoint, https);
      expect(config.apiKey, 'clave-secreta');
    });

    test('RNF-17: envía solo la imagen con la clave en el encabezado',
        () async {
      late Map<String, String> sentHeaders;
      late Uint8List sentBody;
      final adapter = CloudOcrAdapter(
        CloudOcrConfig(endpoint: https, apiKey: 'clave'),
        transport: (uri, headers, body, cancel) async {
          sentHeaders = headers;
          sentBody = body;
          return OcrHttpResponse(200, jsonEncode({'text': legible}));
        },
      );
      expect(await adapter.recognize(image, OcrCancelToken()), legible);
      expect(sentBody, image);
      expect(sentHeaders[HttpHeaders.authorizationHeader], 'Bearer clave');
      expect(sentHeaders[HttpHeaders.contentTypeHeader], 'image/jpeg');
      expect(sentHeaders.keys, hasLength(3));
    });

    Future<OcrFailureKind> kindOf(OcrTransport transport) async {
      final adapter = CloudOcrAdapter(
        CloudOcrConfig(endpoint: https, apiKey: 'k'),
        transport: transport,
      );
      try {
        await adapter.recognize(image, OcrCancelToken());
      } on OcrException catch (e) {
        return e.kind;
      }
      fail('Se esperaba OcrException');
    }

    test('errores de red, del servicio y respuestas raras', () async {
      expect(
        await kindOf((_, __, ___, ____) =>
            Future.error(const SocketException('sin red'))),
        OcrFailureKind.noConnection,
      );
      expect(
        await kindOf((_, __, ___, ____) =>
            Future.error(const OcrException(OcrFailureKind.timeout))),
        OcrFailureKind.timeout,
      );
      expect(
        await kindOf((_, __, ___, ____) async =>
            const OcrHttpResponse(500, '{"text":"x"}')),
        OcrFailureKind.server,
      );
      expect(
        await kindOf((_, __, ___, ____) async =>
            const OcrHttpResponse(200, 'no es json')),
        OcrFailureKind.server,
      );
      expect(
        await kindOf((_, __, ___, ____) async =>
            const OcrHttpResponse(200, '{"otro": 1}')),
        OcrFailureKind.server,
      );
    });

    test('RNF-16: transporte HTTPS real contra un servidor local con TLS',
        () async {
      final cert = await _selfSignedCertificate(tempDir);
      if (cert == null) {
        markTestSkipped('openssl no está disponible');
        return;
      }
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        SecurityContext()
          ..useCertificateChain(cert.cert)
          ..usePrivateKey(cert.key),
      );
      addTearDown(() => server.close(force: true));
      late List<int> received;
      server.listen((request) async {
        received = await request.fold<List<int>>([], (a, b) => a..addAll(b));
        request.response
          ..statusCode = 200
          ..write(jsonEncode({'text': 'ok ${request.headers.contentType}'}));
        await request.response.close();
      });
      final adapter = CloudOcrAdapter(
        CloudOcrConfig(
          endpoint: Uri.parse('https://localhost:${server.port}/leer'),
          apiKey: 'k',
        ),
        transport: HttpClientTransport(
          context: SecurityContext()..setTrustedCertificates(cert.cert),
        ).call,
      );
      final text = await adapter.recognize(image, OcrCancelToken());
      expect(text, 'ok image/jpeg');
      expect(received, image);
    });

    test('un servidor con certificado no confiable se rechaza', () async {
      final cert = await _selfSignedCertificate(tempDir);
      if (cert == null) {
        markTestSkipped('openssl no está disponible');
        return;
      }
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        SecurityContext()
          ..useCertificateChain(cert.cert)
          ..usePrivateKey(cert.key),
      );
      addTearDown(() => server.close(force: true));
      server.listen((request) => request.response.close());
      final adapter = CloudOcrAdapter(
        CloudOcrConfig(
          endpoint: Uri.parse('https://localhost:${server.port}/leer'),
          apiKey: 'k',
        ),
      );
      await expectLater(
        adapter.recognize(image, OcrCancelToken()),
        throwsA(isA<OcrException>()),
      );
    });
  });
}

/// Adaptador que responde cuando la prueba lo decide.
class _ControlledAdapter implements OcrAdapter {
  final Completer<String> completer = Completer<String>();
  OcrCancelToken? token;

  @override
  Future<String> recognize(Uint8List image, OcrCancelToken cancel) {
    token = cancel;
    return completer.future;
  }
}

/// Crea un certificado autofirmado para localhost con openssl. Devuelve
/// `null` si openssl no existe.
Future<({String cert, String key})?> _selfSignedCertificate(
  Directory dir,
) async {
  final cert = p.join(dir.path, 'cert.pem');
  final key = p.join(dir.path, 'key.pem');
  try {
    final result = await Process.run('openssl', [
      'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1', //
      '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost',
      '-keyout', key, '-out', cert,
    ]);
    return result.exitCode == 0 ? (cert: cert, key: key) : null;
  } on ProcessException {
    return null;
  }
}
