import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'error_utils.dart';
import 'history_service.dart';

// Conditional import: web vs native vs stub
import 'download_helper_stub.dart'
    if (dart.library.html) 'download_helper_web.dart'
    if (dart.library.io) 'download_helper_native.dart';

class DownloadService {
  // ─── TXT ─────────────────────────────────────────────────────────────
  static Future<void> downloadTxt(
    BuildContext context,
    HistoryRecord record,
  ) async {
    try {
      final content =
          '${record.templateIcon} ${record.templateName}\n'
          '日期：${_formatDate(record.createdAt)}\n'
          '${'=' * 40}\n\n'
          '${record.result}\n';

      await platformDownloadText(
        content,
        'text/plain;charset=utf-8',
        '${_sanitizeFileName(record.templateName)}.txt',
      );
    } catch (e) {
      debugPrint('TXT export failed: ${sanitizeForDebug(e)}');
      if (context.mounted) _showError(context);
    }
  }

  // ─── PDF ─────────────────────────────────────────────────────────────
  static Future<void> downloadPdf(
    BuildContext context,
    HistoryRecord record,
  ) async {
    try {
      final bytes = await _buildPdfBytes(record);
      await platformDownloadBytes(
        bytes,
        'application/pdf',
        '${_sanitizeFileName(record.templateName)}.pdf',
      );
    } catch (e) {
      debugPrint('PDF export failed: ${sanitizeForDebug(e)}');
      if (context.mounted) _showError(context);
    }
  }

  // ─── Word ─────────────────────────────────────────────────────────────
  static Future<void> downloadWord(
    BuildContext context,
    HistoryRecord record,
  ) async {
    try {
      final html = _buildWordHtml(record);
      await platformDownloadText(
        html,
        'text/html;charset=utf-8',
        '${_sanitizeFileName(record.templateName)}.html',
      );
    } catch (e) {
      debugPrint('HTML export failed: ${sanitizeForDebug(e)}');
      if (context.mounted) _showError(context);
    }
  }

  // ─── PDF builder ──────────────────────────────────────────────────────
  static Future<List<int>> _buildPdfBytes(HistoryRecord record) async {
    final pdf = pw.Document();
    // Noto Sans TC 支援繁體中文，從 Google Fonts 動態載入嵌入 PDF
    final font = await PdfGoogleFonts.notoSansTCRegular();
    final boldFont = await PdfGoogleFonts.notoSansTCBold();
    final lines = record.result.split('\n');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (ctx) => [
          pw.Text(
            record.templateName,
            style: pw.TextStyle(font: boldFont, fontSize: 20),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            '日期：${_formatDate(record.createdAt)}',
            style: pw.TextStyle(
              font: font,
              fontSize: 11,
              color: PdfColors.grey600,
            ),
          ),
          pw.Divider(),
          pw.SizedBox(height: 8),
          ...lines.map((line) {
            if (line.startsWith('# ')) {
              return pw.Padding(
                padding: const pw.EdgeInsets.only(top: 12, bottom: 4),
                child: pw.Text(
                  line.substring(2),
                  style: pw.TextStyle(font: boldFont, fontSize: 16),
                ),
              );
            } else if (line.startsWith('## ')) {
              return pw.Padding(
                padding: const pw.EdgeInsets.only(top: 8, bottom: 2),
                child: pw.Text(
                  line.substring(3),
                  style: pw.TextStyle(font: boldFont, fontSize: 13),
                ),
              );
            } else if (line.startsWith('- [ ] ') || line.startsWith('- [x] ')) {
              final done = line.startsWith('- [x] ');
              return pw.Padding(
                padding: const pw.EdgeInsets.only(left: 12, bottom: 2),
                child: pw.Text(
                  '${done ? '☑' : '☐'} ${line.substring(6)}',
                  style: pw.TextStyle(font: font, fontSize: 11),
                ),
              );
            } else if (line.startsWith('* ') || line.startsWith('- ')) {
              return pw.Padding(
                padding: const pw.EdgeInsets.only(left: 12, bottom: 2),
                child: pw.Text(
                  '• ${line.substring(2)}',
                  style: pw.TextStyle(font: font, fontSize: 11),
                ),
              );
            } else if (line.trim() == '---') {
              return pw.Divider(color: PdfColors.grey400);
            } else if (line.trim().isEmpty) {
              return pw.SizedBox(height: 4);
            } else {
              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 2),
                child: pw.Text(
                  line.replaceAll('**', ''),
                  style: pw.TextStyle(font: font, fontSize: 11),
                ),
              );
            }
          }),
        ],
      ),
    );

    return await pdf.save();
  }

  // ─── Word HTML builder ────────────────────────────────────────────────
  static String _buildWordHtml(HistoryRecord record) {
    final lines = record.result.split('\n');
    final buffer = StringBuffer();

    buffer.write('''<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<style>
  body { font-family: Arial, sans-serif; font-size: 12pt; margin: 40px; }
  h1 { font-size: 18pt; color: #3949AB; }
  h2 { font-size: 14pt; color: #5C6BC0; }
  p { line-height: 1.6; }
  hr { border: 1px solid #ccc; }
  .meta { color: #888; font-size: 10pt; }
  .checkbox { margin-left: 20px; }
</style>
</head>
<body>
<h1>${record.templateIcon} ${_escapeHtml(record.templateName)}</h1>
<p class="meta">日期：${_formatDate(record.createdAt)}</p>
<hr>
''');

    for (final line in lines) {
      if (line.startsWith('# ')) {
        buffer.write('<h1>${_escapeHtml(line.substring(2))}</h1>\n');
      } else if (line.startsWith('## ')) {
        buffer.write('<h2>${_escapeHtml(line.substring(3))}</h2>\n');
      } else if (line.startsWith('- [ ] ')) {
        buffer.write(
          '<p class="checkbox">☐ ${_escapeHtml(line.substring(6))}</p>\n',
        );
      } else if (line.startsWith('- [x] ')) {
        buffer.write(
          '<p class="checkbox">☑ ${_escapeHtml(line.substring(6))}</p>\n',
        );
      } else if (line.startsWith('* ') || line.startsWith('- ')) {
        buffer.write('<p>• ${_escapeHtml(line.substring(2))}</p>\n');
      } else if (line.trim() == '---') {
        buffer.write('<hr>\n');
      } else if (line.trim().isEmpty) {
        buffer.write('<br>\n');
      } else {
        final html = _escapeHtml(line).replaceAllMapped(
          RegExp(r'\*\*(.+?)\*\*'),
          (m) => '<strong>${m[1]}</strong>',
        );
        buffer.write('<p>$html</p>\n');
      }
    }

    buffer.write('</body></html>');
    return buffer.toString();
  }

  // ─── Helpers ──────────────────────────────────────────────────────────
  static String _formatDate(DateTime dt) {
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  static String _sanitizeFileName(String name) =>
      name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

  static String _escapeHtml(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static void _showError(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('匯出失敗，請稍後再試。')));
  }
}
