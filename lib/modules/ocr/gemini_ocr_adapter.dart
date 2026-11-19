/// M-05 · Proveedor de OCR con la API de Gemini de Google AI Studio
/// (RNF-16 a RNF-18, RNF-32; ver docs/arquitectura.md, sección 5.2).
///
/// Envía la foto comprimida del recibo, por HTTPS, al modelo de Gemini y
/// le pide los datos ya separados en JSON (comercio, fecha y total), con
/// un esquema fijo. Ese JSON se convierte a renglones canónicos
/// ("TOTAL $123.45") que entiende el mismo [ReceiptParser] que usan los
/// demás proveedores; si el modelo no respondiera JSON, se usa su texto tal
/// cual.
///
/// ```text
/// POST https://generativelanguage.googleapis.com/v1beta/models/<modelo>:generateContent
/// x-goog-api-key: <clave>
/// {"contents":[{"parts":[{"text":"<instrucción>"},
///   {"inline_data":{"mime_type":"image/jpeg","data":"<base64>"}}]}],
///  "generationConfig":{"responseMimeType":"application/json", ...}}
///
/// 200 OK  {"candidates":[{"content":{"parts":[{"text":"{\"total\":...}"}]}}]}
/// ```
///
/// La clave es la del equipo (Google AI Studio) y se inyecta al compilar
/// con `--dart-define=SPENDY_GEMINI_API_KEY=...`. Nunca va en el
/// repositorio. Quien tenga el APK puede extraerla, así que en AI Studio
/// debe tener límite de cuota (ver docs/firma_release.md). Para desarrollo
/// en escritorio también se lee de la variable de entorno del mismo nombre.
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

  /// Modelo fijado al compilar (opcional).
  static const String compiledModel = String.fromEnvironment(modelKey);

  /// Clave del equipo, inyectada al compilar. Vacía en pruebas y en
  /// compilaciones sin `--dart-define`.
  static const String compiledApiKey = String.fromEnvironment(apiKeyKey);
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

  /// Lee la configuración de [environment] (por defecto, las variables del
  /// sistema; útil en escritorio y en pruebas). `null` si no hay clave.
  static GeminiOcrConfig? fromEnvironment({
    Map<String, String>? environment,
    String compiledKey = GeminiEnvironment.compiledApiKey,
  }) {
    final env = environment ?? Platform.environment;
    final key = _pick(compiledKey, env[GeminiEnvironment.apiKeyKey]);
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

/// Instrucción que acompaña a la foto.
const String geminiReceiptPrompt =
    'Lee este recibo o ticket de compra de México y extrae: el nombre del '
    'comercio (como aparece en el encabezado, sin RFC ni dirección), la '
    'fecha de la compra en formato AAAA-MM-DD y el TOTAL pagado (no el '
    'subtotal, ni el IVA, ni el efectivo recibido, ni el cambio). Si un dato '
    'no se ve con claridad, déjalo en null; no inventes nada. Si la imagen '
    'no es un recibo o no se puede leer, pon "legible" en false.';

/// Esquema de la respuesta JSON (subconjunto OpenAPI que acepta Gemini).
const Map<String, Object> geminiReceiptSchema = {
  'type': 'OBJECT',
  'properties': {
    'legible': {'type': 'BOOLEAN'},
    'comercio': {'type': 'STRING', 'nullable': true},
    'fecha': {'type': 'STRING', 'nullable': true},
    'total': {'type': 'NUMBER', 'nullable': true},
  },
  'required': ['legible'],
};

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
    return receiptJsonToText(parseGeminiResponse(response));
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
    'generationConfig': {
      'temperature': 0,
      'responseMimeType': 'application/json',
      'responseSchema': geminiReceiptSchema,
    },
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

/// Convierte el JSON de Gemini (`comercio`, `fecha`, `total`, `legible`) a
/// renglones que entiende [ReceiptParser]: el comercio, "FECHA DD/MM/AAAA"
/// y "TOTAL $1234.50". Lo que no venga se omite; si no es legible o no
/// trae nada, devuelve texto vacío (recibo ilegible, RF-29). Si [text] no
/// es un objeto JSON, lo devuelve tal cual (respuesta de texto libre).
String receiptJsonToText(String text) {
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    return text;
  }
  if (json is! Map) return text;
  if (json['legible'] == false) return '';
  final lines = <String>[];
  final merchant = json['comercio'];
  if (merchant is String && merchant.trim().isNotEmpty) {
    lines.add(merchant.trim().replaceAll(RegExp(r'\s+'), ' '));
  }
  final date = _isoToDmy(json['fecha']);
  if (date != null) lines.add('FECHA $date');
  final total = json['total'];
  if (total is num && total > 0) {
    lines.add('TOTAL \$${total.toStringAsFixed(2)}');
  } else if (total is String && total.trim().isNotEmpty) {
    lines.add('TOTAL ${total.trim()}');
  }
  return lines.join('\n');
}

final RegExp _isoDate = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$');

String? _isoToDmy(Object? value) {
  if (value is! String) return null;
  final m = _isoDate.firstMatch(value.trim());
  if (m == null) return null;
  final d = m.group(3)!.padLeft(2, '0');
  final mo = m.group(2)!.padLeft(2, '0');
  return '$d/$mo/${m.group(1)}';
}

/// Usa Gemini cuando hay clave guardada en Ajustes y si no, [fallback]
/// (ML Kit en el teléfono). La clave se lee en cada lectura, así que
/// capturarla o quitarla en Ajustes aplica de inmediato, sin reiniciar.
class KeyedGeminiOcrAdapter implements OcrAdapter {
  KeyedGeminiOcrAdapter({
    required Future<String?> Function() readKey,
    required OcrAdapter fallback,
    String? model,
    OcrTransport? transport,
  })  : _readKey = readKey,
        _fallback = fallback,
        _model = model,
        _transport = transport;

  final Future<String?> Function() _readKey;
  final OcrAdapter _fallback;
  final String? _model;
  final OcrTransport? _transport;

  @override
  Future<String> recognize(Uint8List image, OcrCancelToken cancel) async {
    final key = await _readKey();
    if (key == null || key.isEmpty) return _fallback.recognize(image, cancel);
    final config = GeminiOcrConfig(apiKey: key, model: _model);
    return GeminiOcrAdapter(config, transport: _transport)
        .recognize(image, cancel);
  }
}
