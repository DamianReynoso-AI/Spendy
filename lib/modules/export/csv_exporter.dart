/// M-08 · Exportación del resumen anual a CSV (RF-41, RF-42; RNF-37,
/// RNF-38; CA-108, CA-110).
///
/// UTF-8 precedido por el BOM (U+FEFF) para que Excel y Google Sheets lean
/// bien los acentos y la "ñ". Separador coma y fin de línea CRLF.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../summary/annual_summary_calculator.dart';
import 'exporter.dart';

/// Marca de orden de bytes que va al inicio del archivo.
const String utf8Bom = '﻿';

/// Pone un campo entre comillas si trae coma, comillas o salto de línea.
String csvField(String value) {
  if (!value.contains(RegExp('[",\r\n]'))) return value;
  return '"${value.replaceAll('"', '""')}"';
}

/// Generador CSV.
class CsvExporter implements SummaryExporter {
  const CsvExporter();

  @override
  ExportFormat get format => ExportFormat.csv;

  /// Texto del CSV, sin BOM (útil para pruebas).
  String buildText(AnnualSummary summary, DateTime generatedAt) {
    final rows = <List<String>>[
      [ExportTexts.title],
      [ExportTexts.year, summary.year.toString()],
      [ExportTexts.generatedAt, generatedDate(generatedAt)],
      [],
      [ExportTexts.totals, ExportTexts.amount],
      for (final (label, value) in totalRows(summary)) [label, value],
      [],
      [ExportTexts.byCategory, ExportTexts.amount],
      for (final (label, value) in categoryRows(summary)) [label, value],
    ];
    final lines = rows.map((row) => row.map(csvField).join(','));
    return '${lines.join('\r\n')}\r\n';
  }

  @override
  Future<Uint8List> render(AnnualSummary summary, DateTime generatedAt) async =>
      Uint8List.fromList(
        utf8.encode(utf8Bom + buildText(summary, generatedAt)),
      );
}
