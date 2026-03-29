import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'history_service.dart';

class DownloadService {
  // 下載為 TXT
  static Future<void> downloadTxt(
    BuildContext context,
    HistoryRecord record,
  ) async {
    try {
      final dir = await getTemporaryDirectory();
      final fileName = _sanitizeFileName(record.templateName);
      final file = File('${dir.path}/$fileName.txt');

      final content =
          '''${record.templateIcon} ${record.templateName}
日期：${_formatDate(record.createdAt)}
${'=' * 40}

${record.result}
''';

      await file.writeAsString(content, encoding: SystemEncoding());
      await _shareFile(file.path, '${record.templateName}.txt');
    } catch (e) {
      if (context.mounted) {
        _showError(context, e.toString());
      }
    }
  }

  // 下載為 PDF
  static Future<void> downloadPdf(
    BuildContext context,
    HistoryRecord record,
  ) async {
    try {
      final pdf = pw.Document();
      final font = pw.Font.helvetica();
      final boldFont = pw.Font.helveticaBold();

      // 把 Markdown 轉成純文字段落
      final lines = record.result.split('\n');

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (context) => [
            // 標題
            pw.Text(
              '${record.templateName}',
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
            // 內容逐行渲染
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
              } else if (line.startsWith('- [ ] ') ||
                  line.startsWith('- [x] ')) {
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
                // 去除 Markdown 粗體符號 **
                final cleaned = line.replaceAll('**', '');
                return pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 2),
                  child: pw.Text(
                    cleaned,
                    style: pw.TextStyle(font: font, fontSize: 11),
                  ),
                );
              }
            }),
          ],
        ),
      );

      final dir = await getTemporaryDirectory();
      final fileName = _sanitizeFileName(record.templateName);
      final file = File('${dir.path}/$fileName.pdf');
      await file.writeAsBytes(await pdf.save());
      await _shareFile(file.path, '${record.templateName}.pdf');
    } catch (e) {
      if (context.mounted) {
        _showError(context, e.toString());
      }
    }
  }

  // 下載為 Word（HTML 格式，Word 可直接開啟）
  static Future<void> downloadWord(
    BuildContext context,
    HistoryRecord record,
  ) async {
    try {
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
<h1>${record.templateIcon} ${record.templateName}</h1>
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

      final dir = await getTemporaryDirectory();
      final fileName = _sanitizeFileName(record.templateName);
      final file = File('${dir.path}/$fileName.doc');
      await file.writeAsString(buffer.toString());
      await _shareFile(file.path, '${record.templateName}.doc');
    } catch (e) {
      if (context.mounted) {
        _showError(context, e.toString());
      }
    }
  }

  static Future<void> _shareFile(String path, String name) async {
    await Share.shareXFiles([XFile(path)], subject: name);
  }

  static String _formatDate(DateTime dt) {
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  static String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  static String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  static void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('下載失敗：$message')));
  }
}
