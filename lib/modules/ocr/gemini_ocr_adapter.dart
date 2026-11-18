/// M-05 · Proveedor de OCR con la API de Gemini de Google AI Studio
/// (RNF-16 a RNF-18, RNF-32; ver docs/arquitectura.md, sección 5.2).
///
/// Envía la foto comprimida del recibo, por HTTPS, al modelo de Gemini y
/// le pide transcribir el texto renglón por renglón. Ese texto pasa al
/// mismo [ReceiptParser] que usan los demás proveedores.
///
/// ```text
/// POST https://generativelanguage.googleapis.com/v1beta/models/<modelo>:generateContent
/// x-goog-api-key: <SPENDY_GEMINI_API_KEY>
/// {"contents":[{"parts":[{"text":"<instrucción>"},
///   {"inline_data":{"mime_type":"image/jpeg","data":"<base64>"}}]}]}
///
/// 200 OK  {"candidates":[{"content":{"parts":[{"text":"<texto>"}]}}]}
/// ```
///
/// La clave se lee de `--dart-define-from-file=.env` (RNF-18). `.env` no se
/// sube al repositorio.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'cloud_ocr_adapter.dart';
import 'ocr_adapter.dart';

/// Nombres de las variables de configuración de Gemini.
class GeminiEnvironment {
  GeminiEnvironment._();

  static const String apiKeyKey = 'SPENDY_GEMINI_API_KEY';
  static const String modelKey = 'SPENDY_GEMINI_MODEL';

  /// Modelos por omisión, en orden: el Flash-Lite vigente (el más rápido y
  /// con más cuota gratuita) y, si está saturado, el Flash vigente. Son
  /// alias de Google que siempre apuntan a la versión actual.
  static const List<String> defaultModels = [
    'gemini-flash-lite-latest',
    'gemini-flash-latest',
  ];

  static const String compiledApiKey = String.fromEnvironment(apiKeyKey);
  static const String compiledModel = String.fromEnvironment(modelKey);

  /// `true` si esta compilación trae clave de Gemini.
  static const bool isCompiledIn = compiledApiKey != '';
}

/// Clave y modelos de Gemini.
class GeminiOcrConfig {
  /// [model] acepta uno o varios modelos separados por comas, en orden de
  /// preferencia.
  GeminiOcrConfig({required this.apiKey, String? model})
      : models = _parseModels(model);

  final String apiKey;

  /// Modelos a intentar, en orden. Nunca está vacía.
  final List<String> models;

  /// Endpoint de [model]. Siempre HTTPS (RNF-16).
  Uri endpointFor(String model) => Uri.https(
        'generativelanguage.googleapis.com',
        '/v1beta/models/$model:generateContent',
      );

  static List<String> _parseModels(String? text) {
    final list = (text ?? '')
        .split(',')
        .map((m) => m.trim())
        .where((m) => m.isNotEmpty)
        .toList();
    return list.isEmpty ? GeminiEnvironment.defaultModels : list;
  }

  /// Lee la configuración de `--dart-define` o, si no hay, de [environment]
  /// (por defecto, las variables del sistema). `null` si no hay clave.
  static GeminiOcrConfig? fromEnvironment({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    final key = _pick(
        GeminiEnvironment.compiledApiKey, env[GeminiEnvironment.apiKeyKey]);
    if (key == null) return null;
    final model =
        _pick(GeminiEnvironment.compiledModel, env[GeminiEnvironment.modelKey]);
    return GeminiOcrConfig(apiKey: key, model: model);
  }

  static String? _pick(String compiled, String? runtime) {
    final value = (compiled.isNotEmpty ? compiled : (runtime ?? '')).trim();
    return value.isEmpty ? null : value;
  }
}

/// Instrucción que acompaña a la foto. Pide texto plano con cada concepto
/// junto a su importe, que es lo que entiende [ReceiptParser].
const String geminiReceiptPrompt =
    'Transcribe el texto de este recibo o ticket de compra tal como está '
    'impreso, renglón por renglón y de arriba abajo. Deja en el mismo '
    'renglón cada concepto con su importe (por ejemplo "TOTAL \$123.45"). '
    'Conserva las fechas como aparecen. Responde solo con el texto, sin '
    'comentarios, sin Markdown y sin inventar nada. Si la imagen no es un '
    'recibo o no se puede leer, responde con un texto vacío.';

/// Adaptador de Gemini. Solo envía la imagen y la instrucción fija; nunca
/// montos, notas ni otros datos de la persona (RNF-17).
class GeminiOcrAdapter implements OcrAdapter {
  GeminiOcrAdapter(this.config, {OcrTransport? transport})
      : _transport = transport ?? HttpClientTransport().call;

  final GeminiOcrConfig config;
  final OcrTransport _transport;

  /// Códigos con los que vale la pena probar el siguiente modelo: modelo
  /// retirado (404), sin cuota (429) o saturado (500, 503).
  static const Set<int> _tryNextModel = {404, 429, 500, 503};

  @override
  Future<String> recognize(Uint8List image, OcrCancelToken cancel) async {
    final body = buildGeminiRequest(image);
    late OcrHttpResponse response;
    for (final model in config.models) {
      response = await _send(model, body, cancel);
      if (!_tryNextModel.contains(response.statusCode)) break;
      if (cancel.isCancelled) break;
    }
    return parseGeminiResponse(response);
  }

  Future<OcrHttpResponse> _send(
    String model,
    Uint8List body,
    OcrCancelToken cancel,
  ) async {
    try {
      return await _transport(
        config.endpointFor(model),
        {
          'x-goog-api-key': config.apiKey,
          HttpHeaders.contentTypeHeader: 'application/json',
          HttpHeaders.acceptHeader: 'application/json',
        },
        body,
        cancel,
      );
    } on OcrException {
      rethrow;
    } on Object catch (e) {
      throw OcrException(OcrFailureKind.noConnection, e.runtimeType.toString());
    }
  }
}

/// Cuerpo JSON de la petición, en bytes UTF-8.
Uint8List buildGeminiRequest(Uint8List image) {
  final body = {
    'contents': [
      {
        'parts': [
          {'text': geminiReceiptPrompt},
          {
            'inline_data': {
              'mime_type': 'image/jpeg',
              'data': base64Encode(image),
            },
          },
        ],
      },
    ],
    'generationConfig': {'temperature': 0},
  };
  return Uint8List.fromList(utf8.encode(jsonEncode(body)));
}

/// Junta el texto de la primera respuesta de Gemini. Un código distinto de
/// 200 o una respuesta sin texto cuenta como error del servicio; el código
/// y el mensaje de Google quedan en [OcrException.detail] para la bitácora.
String parseGeminiResponse(OcrHttpResponse response) {
  if (response.statusCode != HttpStatus.ok) {
    throw OcrException(
      OcrFailureKind.server,
      'HTTP ${response.statusCode} ${_googleError(response.body)}'.trim(),
    );
  }
  try {
    final json = jsonDecode(response.body);
    final candidates = json is Map ? json['candidates'] : null;
    if (candidates is List && candidates.isNotEmpty) {
      final content = (candidates.first as Map)['content'];
      final parts = content is Map ? content['parts'] : null;
      if (parts is List) {
        return parts
            .whereType<Map>()
            .map((p) => p['text'])
            .whereType<String>()
            .join()
            .trim();
      }
      // Sin "parts": Gemini bloqueó o no generó respuesta.
      return '';
    }
  } on FormatException {
    // Se trata igual que una respuesta sin candidatos.
  } on TypeError {
    // Igual.
  }
  throw const OcrException(OcrFailureKind.server, 'respuesta sin candidatos');
}

/// Saca `error.status` y `error.message` del cuerpo de error de Google, sin
/// la clave (Google no la incluye) y recortado.
String _googleError(String body) {
  try {
    final json = jsonDecode(body);
    final error = json is Map ? json['error'] : null;
    if (error is Map) {
      final text = '${error['status'] ?? ''}: ${error['message'] ?? ''}';
      return text.length > 200 ? text.substring(0, 200) : text;
    }
  } on FormatException {
    // Cuerpo que no es JSON.
  }
  return '';
}
