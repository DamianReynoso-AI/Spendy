// RNF-42 y RNF-13 con los 30 recibos reales de test/fixtures/receipts/ y
// el proveedor de OCR real (CloudOcrAdapter). Si faltan las fotos o la
// configuración del proveedor, la prueba se omite: no inventa resultados.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:spendy/config/app_config.dart';
import 'package:spendy/core/error_logger.dart';
import 'package:spendy/modules/ocr/cloud_ocr_adapter.dart';
import 'package:spendy/modules/ocr/ocr_service.dart';
import 'package:spendy/modules/receipts/receipt_service.dart';

const String fixtures = 'test/fixtures/receipts';
const int requiredReceipts = 30;

void main() {
  test('RNF-42 / RNF-13: 30 recibos reales con el proveedor de OCR', () async {
    final expectedFile = File(p.join(fixtures, 'expected.json'));
    final config = CloudOcrConfig.fromEnvironment();
    if (!expectedFile.existsSync() || config == null) {
      markTestSkipped(
        'Faltan $fixtures/expected.json con las fotos o las variables '
        '${OcrEnvironment.endpointKey} y ${OcrEnvironment.apiKeyKey}.',
      );
      return;
    }
    final cases = (jsonDecode(expectedFile.readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
    expect(cases.length, greaterThanOrEqualTo(requiredReceipts));
    final service = OcrService(
      adapter: CloudOcrAdapter(config),
      logger: ErrorLogger(() async => File(p.join(fixtures, 'ocr.log'))),
    );
    var hits = 0;
    var onTime = 0;
    for (final item in cases) {
      final raw =
          File(p.join(fixtures, item['file'] as String)).readAsBytesSync();
      final watch = Stopwatch()..start();
      final outcome = await service.start(compressReceiptImage(raw)).result;
      watch.stop();
      final read = outcome is OcrRead ? outcome.receipt.amountText : null;
      final ok = read == item['total'];
      if (ok) hits++;
      if (watch.elapsed <= AppConfig.ocrTargetTime) onTime++;
      // ignore: avoid_print
      print('${item['file']}: leído=$read esperado=${item['total']} '
          '${ok ? 'OK' : 'FALLA'} ${watch.elapsedMilliseconds} ms');
    }
    final accuracy = hits / cases.length;
    final timely = onTime / cases.length;
    // ignore: avoid_print
    print('Acierto en monto: ${(accuracy * 100).toStringAsFixed(1)} % · '
        'En 8 s o menos: ${(timely * 100).toStringAsFixed(1)} %');
    expect(accuracy, greaterThanOrEqualTo(0.8), reason: 'RNF-42');
    expect(timely, greaterThanOrEqualTo(0.9), reason: 'RNF-13');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
