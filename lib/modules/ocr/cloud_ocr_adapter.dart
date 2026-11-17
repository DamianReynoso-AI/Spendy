/// M-05 · Proveedor de OCR en la nube por HTTPS (RNF-16 a RNF-18, RNF-32).
///
/// Contrato que espera del servicio (independiente del proveedor; si el
/// proveedor elegido usa otro formato, se adapta en un servicio intermedio
/// o con otra implementación de [OcrAdapter]):
///
/// ```text
/// POST <SPENDY_OCR_ENDPOINT>
/// Authorization: Bearer <SPENDY_OCR_API_KEY>
/// Content-Type: image/jpeg
/// <bytes de la imagen comprimida>
///
/// 200 OK  {"text": "<texto leído del recibo>"}
/// ```
///
/// El endpoint y la clave se leen de variables definidas fuera del código
/// (RNF-18): al compilar con `--dart-define-from-file=ocr.env.json` (archivo
/// que no se sube al repositorio) o, en pruebas de escritorio, de las
/// variables de entorno del sistema.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'ocr_adapter.dart';

/// Nombres de las variables de configuración.
class OcrEnvironment {
  OcrEnvironment._();

  static const String endpointKey = 'SPENDY_OCR_ENDPOINT';
  static const String apiKeyKey = 'SPENDY_OCR_API_KEY';

  /// Valores fijados al compilar con `--dart-define`.
  static const String compiledEndpoint = String.fromEnvironment(endpointKey);
  static const String compiledApiKey = String.fromEnvironment(apiKeyKey);
}

/// Endpoint y clave del servicio.
class CloudOcrConfig {
  CloudOcrConfig({required this.endpoint, required this.apiKey}) {
    if (endpoint.scheme != 'https' || endpoint.host.isEmpty) {
      throw ArgumentError.value(
        endpoint.scheme,
        'endpoint',
        'El servicio de OCR solo se usa por HTTPS (RNF-16)',
      );
    }
  }

  final Uri endpoint;
  final String apiKey;

  /// Lee la configuración de `--dart-define` o, si no hay, de [environment]
  /// (por defecto, las variables del sistema). Devuelve `null` si falta el
  /// endpoint o la clave. Lanza [ArgumentError] si el endpoint no es HTTPS.
  static CloudOcrConfig? fromEnvironment({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    final endpoint =
        _pick(OcrEnvironment.compiledEndpoint, env[OcrEnvironment.endpointKey]);
    final apiKey =
        _pick(OcrEnvironment.compiledApiKey, env[OcrEnvironment.apiKeyKey]);
    if (endpoint == null || apiKey == null) return null;
    return CloudOcrConfig(endpoint: Uri.parse(endpoint), apiKey: apiKey);
  }

  static String? _pick(String compiled, String? runtime) {
    final value = compiled.isNotEmpty ? compiled : (runtime ?? '');
    return value.trim().isEmpty ? null : value.trim();
  }
}

/// Respuesta HTTP mínima que necesita el adaptador.
class OcrHttpResponse {
  const OcrHttpResponse(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

/// Envía la petición. [HttpClientTransport] es la real; las pruebas pueden
/// usar otra.
typedef OcrTransport = Future<OcrHttpResponse> Function(
  Uri endpoint,
  Map<String, String> headers,
  Uint8List body,
  OcrCancelToken cancel,
);

/// Transporte con `dart:io` [HttpClient]: no sigue redirecciones (para que
/// nadie pueda bajar la conexión a HTTP) y cierra la conexión al cancelar.
/// El cifrado lo negocia la plataforma (BoringSSL en Android y Dart).
class HttpClientTransport {
  HttpClientTransport({SecurityContext? context}) : _context = context;

  final SecurityContext? _context;

  Future<OcrHttpResponse> call(
    Uri endpoint,
    Map<String, String> headers,
    Uint8List body,
    OcrCancelToken cancel,
  ) async {
    final client = HttpClient(context: _context)
      ..connectionTimeout = const Duration(seconds: 10);
    cancel.onCancel(() => client.close(force: true));
    try {
      final request = await client.postUrl(endpoint);
      request.followRedirects = false;
      headers.forEach(request.headers.set);
      request.add(body);
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      return OcrHttpResponse(response.statusCode, text);
    } finally {
      client.close();
    }
  }
}

/// Adaptador HTTPS. Solo envía la imagen; nunca montos, notas ni otros
/// datos de la persona (RNF-17).
class CloudOcrAdapter implements OcrAdapter {
  CloudOcrAdapter(this.config, {OcrTransport? transport})
      : _transport = transport ?? HttpClientTransport().call;

  final CloudOcrConfig config;
  final OcrTransport _transport;

  @override
  Future<String> recognize(Uint8List image, OcrCancelToken cancel) async {
    final OcrHttpResponse response;
    try {
      response = await _transport(
        config.endpoint,
        {
          HttpHeaders.authorizationHeader: 'Bearer ${config.apiKey}',
          HttpHeaders.contentTypeHeader: 'image/jpeg',
          HttpHeaders.acceptHeader: 'application/json',
        },
        image,
        cancel,
      );
    } on OcrException {
      rethrow;
    } on Object {
      throw const OcrException(OcrFailureKind.noConnection);
    }
    return parseOcrResponse(response);
  }
}

/// Saca el texto de una respuesta `{"text": "..."}`; cualquier otra cosa
/// cuenta como error del servicio.
String parseOcrResponse(OcrHttpResponse response) {
  if (response.statusCode != HttpStatus.ok) {
    throw const OcrException(OcrFailureKind.server);
  }
  try {
    final json = jsonDecode(response.body);
    if (json is Map && json['text'] is String) return json['text'] as String;
  } on FormatException {
    // Se trata igual que un cuerpo sin "text".
  }
  throw const OcrException(OcrFailureKind.server);
}
