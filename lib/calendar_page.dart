import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'history_service.dart';
import 'history_page.dart';
import 'transitions.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  final _service = HistoryService();
  Map<DateTime, List<HistoryRecord>> _events = {};
  List<HistoryRecord> _selectedRecords = [];
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    final records = await _service.loadAll();
    final Map<DateTime, List<HistoryRecord>> events = {};

    for (final record in records) {
      // 只取年月日，忽略時分秒
      final day = DateTime(
        record.createdAt.year,
        record.createdAt.month,
        record.createdAt.day,
      );
      events.putIfAbsent(day, () => []).add(record);
    }

    setState(() {
      _events = events;
      _isLoading = false;
      // 預設選今天（如果有紀錄的話）
      final today = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
      );
      if (events.containsKey(today)) {
        _selectedDay = today;
        _selectedRecords = events[today] ?? [];
      }
    });
  }

  List<HistoryRecord> _getEventsForDay(DateTime day) {
    final key = DateTime(day.year, day.month, day.day);
    return _events[key] ?? [];
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    setState(() {
      _selectedDay = selectedDay;
      _focusedDay = focusedDay;
      _selectedRecords = _getEventsForDay(selectedDay);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('日曆檢視'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                TableCalendar<HistoryRecord>(
                  firstDay: DateTime(2024),
                  lastDay: DateTime(2030),
                  focusedDay: _focusedDay,
                  selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                  eventLoader: _getEventsForDay,
                  onDaySelected: _onDaySelected,
                  onPageChanged: (focusedDay) {
                    setState(() => _focusedDay = focusedDay);
                  },
                  calendarBuilders: CalendarBuilders(
                    defaultBuilder: (context, day, focusedDay) {
                      final hasEvents = _getEventsForDay(day).isNotEmpty;
                      if (hasEvents) {
                        return Container(
                          margin: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withOpacity(0.12),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${day.day}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      }
                      return null;
                    },
                    outsideBuilder: (context, day, focusedDay) {
                      final hasEvents = _getEventsForDay(day).isNotEmpty;
                      if (hasEvents) {
                        return Container(
                          margin: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withOpacity(0.08),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${day.day}',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withOpacity(0.6),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      }
                      return null;
                    },
                  ),
                  calendarStyle: CalendarStyle(
                    // 選中的日期
                    selectedDecoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    selectedTextStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                    // 今天
                    todayDecoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    todayTextStyle: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                    // 有紀錄的日期：改變文字顏色，不顯示小點
                    markerDecoration: const BoxDecoration(
                      color: Colors.transparent,
                    ),
                    markersMaxCount: 0,
                    // 有事件的日期用 CalendarBuilders 處理
                  ),
                  headerStyle: const HeaderStyle(
                    formatButtonVisible: false,
                    titleCentered: true,
                  ),
                  locale: 'zh_TW',
                ),
                const Divider(height: 1),
                // 選中日期的紀錄列表
                Expanded(
                  child: _selectedDay == null
                      ? const Center(
                          child: Text(
                            '點選日期查看當天的筆記',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : _selectedRecords.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.event_busy,
                                size: 48,
                                color: Colors.grey,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '${_selectedDay!.month}月${_selectedDay!.day}日 沒有筆記',
                                style: const TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _selectedRecords.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final record = _selectedRecords[index];
                            return Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Colors.indigo.shade100),
                              ),
                              child: ListTile(
                                leading: Text(
                                  record.templateIcon,
                                  style: const TextStyle(fontSize: 28),
                                ),
                                title: Text(
                                  record.templateName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  '${record.createdAt.hour.toString().padLeft(2, '0')}:'
                                  '${record.createdAt.minute.toString().padLeft(2, '0')}',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => Navigator.push(
                                  context,
                                  FadeRoute(
                                    page: HistoryDetailPage(record: record),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
