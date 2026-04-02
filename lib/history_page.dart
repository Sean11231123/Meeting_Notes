import 'dart:convert'; // 必須匯入以支援 json 處理 (若 Service 有用到)
import 'package:flutter/material.dart';
import 'history_service.dart';
import 'download_service.dart';
import 'calendar_page.dart';
import 'transitions.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final _service = HistoryService();
  List<HistoryRecord> _records = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final records = await _service.loadAll();
    // 確保列表是依照時間排序（最新的在前）
    records.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (mounted) {
      setState(() {
        _records = records;
        _isLoading = false;
      });
    }
  }

  Future<void> _delete(String id) async {
    await _service.delete(id);
    await _load();
  }

  // --- 已刪除原本錯誤的 updateName 方法，請統一使用 HistoryService ---

  String _formatDate(DateTime dt) {
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('歷史紀錄'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: '日曆檢視',
            onPressed: () =>
                Navigator.push(context, FadeRoute(page: const CalendarPage())),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    '還沒有任何紀錄',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _records.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final record = _records[index];
                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.indigo.shade100),
                  ),
                  child: ListTile(
                    leading: Text(
                      record.displayIcons,
                      style: const TextStyle(fontSize: 28),
                    ),
                    title: Text(
                      record.templateName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      record.templateNames.length > 1
                          ? '${record.displayName} · ${_formatDate(record.createdAt)}'
                          : _formatDate(record.createdAt),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _confirmDelete(record.id),
                    ),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        FadeRoute(page: HistoryDetailPage(record: record)),
                      );
                      _load();
                    },
                  ),
                );
              },
            ),
    );
  }

  void _confirmDelete(String id) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('刪除紀錄'),
        content: const Text('確定要刪除這筆紀錄嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _delete(id);
            },
            child: const Text('刪除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

// HistoryDetailPage 部分邏輯基本正確，僅微調細節
class HistoryDetailPage extends StatefulWidget {
  final HistoryRecord record;
  const HistoryDetailPage({super.key, required this.record});

  @override
  State<HistoryDetailPage> createState() => _HistoryDetailPageState();
}

class _HistoryDetailPageState extends State<HistoryDetailPage> {
  late String _currentName;
  final _service = HistoryService();

  @override
  void initState() {
    super.initState();
    _currentName = widget.record.templateName;
  }

  // 格式化日期建議統一寫法
  String _formatDate(DateTime dt) {
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _editName() async {
    final controller = TextEditingController(text: _currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('編輯名稱'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '輸入新名稱',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
            ),
            child: const Text('儲存'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != _currentName) {
      await _service.updateName(widget.record.id, newName);
      setState(() => _currentName = newName);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('名稱已更新')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 這裡使用更新後的 _currentName
    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          // 讓標題區域更容易點擊編輯
          onTap: _editName,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  '${widget.record.templateIcon} $_currentName',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.edit, size: 16, color: Colors.black54),
            ],
          ),
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.download),
            onSelected: (format) async {
              // 建立更新後的 record 物件傳給下載服務
              final updatedRecord = HistoryRecord(
                id: widget.record.id,
                templateName: _currentName,
                templateIcon: widget.record.templateIcon,
                result: widget.record.result,
                createdAt: widget.record.createdAt,
              );
              if (format == 'txt')
                await DownloadService.downloadTxt(context, updatedRecord);
              if (format == 'pdf')
                await DownloadService.downloadPdf(context, updatedRecord);
              if (format == 'word')
                await DownloadService.downloadWord(context, updatedRecord);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'txt', child: Text('📄 下載 TXT')),
              PopupMenuItem(value: 'pdf', child: Text('📕 下載 PDF')),
              PopupMenuItem(
                value: 'word',
                child: Text('📄 下載 HTML（可用 Word 開啟）'),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _formatDate(widget.record.createdAt),
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                ),
              ),
              child: MarkdownBody(
                data: widget.record.result,
                selectable: true,
                styleSheet: MarkdownStyleSheet(
                  h1: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  h2: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    height: 2.0,
                  ),
                  p: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  listBullet: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
