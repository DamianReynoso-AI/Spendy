/// M-08 · Contrato de exportación del resumen anual (RF-41 a RF-43;
/// RNF-33, RNF-37).
///
/// Cada formato recibe el resumen ya calculado por M-07 y no recalcula
/// cifras (RNF-33).
library;

import 'dart:typed_data';

import '../../core/formatters.dart';
import '../summary/annual_summary_calculator.dart';

/// Formatos disponibles.
enum ExportFormat {
  csv('csv', 'text/csv'),
  pdf('pdf', 'application/pdf');

  const ExportFormat(this.extension, this.mimeType);
  final String extension;
  final String mimeType;
}

/// Nombre exacto del archivo: `spendy_resumen_AAAA.csv` o `.pdf`
/// (RF-43, CA-107).
String exportFileName(int year, ExportFormat format) =>
    'spendy_resumen_${year.toString().padLeft(4, '0')}.${format.extension}';

/// Títulos de los cuatro bloques (RF-42, GRA-02), en español de México.
class ExportTexts {
  ExportTexts._();

  static const String title = 'Resumen anual SPENDY';
  static const String year = 'Año consultado';
  static const String generatedAt = 'Fecha de generación';
  static const String totals = 'Totales del año';
  static const String income = 'Ingresos';
  static const String expense = 'Egresos';
  static const String difference = 'Diferencia (ingresos - egresos)';
  static const String byCategory = 'Gastos por categoría';
  static const String category = 'Categoría';
  static const String amount = 'Monto';
  static const String concept = 'Concepto';
}

/// Filas de los bloques 3 y 4, ya con formato MXN. Las comparten CSV y
/// PDF para que digan exactamente lo mismo.
List<(String, String)> totalRows(AnnualSummary summary) => [
      (ExportTexts.income, summary.formattedIncome),
      (ExportTexts.expense, summary.formattedExpense),
      (ExportTexts.difference, summary.formattedDifference),
    ];

List<(String, String)> categoryRows(AnnualSummary summary) => [
      for (final total in summary.byCategory) (total.name, total.formatted),
    ];

/// Fecha de generación en DD/MM/AAAA, sin depender del idioma del
/// teléfono (RNF-37, CA-110).
String generatedDate(DateTime generatedAt) => formatDate(generatedAt);

/// Un generador de archivo.
abstract interface class SummaryExporter {
  ExportFormat get format;

  /// Bytes del archivo con los cuatro bloques (RF-42).
  Future<Uint8List> render(AnnualSummary summary, DateTime generatedAt);
}
