/// M-08 · Exportación del resumen anual a PDF estándar (RF-41, RF-42;
/// RNF-37, RNF-38).
///
/// Usa las fuentes estándar del PDF (Helvetica con codificación
/// WinAnsi), que cubren los acentos y la "ñ" y abren en cualquier visor.
/// No lleva gráficas (sección 4).
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../summary/annual_summary_calculator.dart';
import 'exporter.dart';

/// Generador PDF.
class PdfExporter implements SummaryExporter {
  const PdfExporter();

  @override
  ExportFormat get format => ExportFormat.pdf;

  @override
  Future<Uint8List> render(AnnualSummary summary, DateTime generatedAt) {
    final document = pw.Document(
      title: '${ExportTexts.title} ${summary.year}',
      creator: 'SPENDY',
    );
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(48),
        build: (_) => _content(summary, generatedAt),
      ),
    );
    return document.save();
  }

  pw.Widget _content(AnnualSummary summary, DateTime generatedAt) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          ExportTexts.title,
          style:
              const pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 12),
        pw.Text('${ExportTexts.year}: ${summary.year}'),
        pw.Text('${ExportTexts.generatedAt}: ${generatedDate(generatedAt)}'),
        pw.SizedBox(height: 20),
        _table(ExportTexts.totals, totalRows(summary)),
        pw.SizedBox(height: 20),
        _table(ExportTexts.byCategory, categoryRows(summary)),
      ],
    );
  }

  pw.Widget _table(String title, List<(String, String)> rows) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style:
              const pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headers: [ExportTexts.concept, ExportTexts.amount],
          data: [
            for (final (label, value) in rows) [label, value],
          ],
          cellAlignments: {1: pw.Alignment.centerRight},
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
        ),
      ],
    );
  }
}
