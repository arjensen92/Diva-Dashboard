import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/calendar_service.dart';
import '../main.dart';

/// State for the Calendar card + full-screen view.
/// [events] is the raw list returned by Google Calendar — untyped because
/// the googleapis event object is serialized to Map on the service side.
/// [weekOffset] is the week-view scroll position relative to today (0 = this week).
class CalendarState {
  final bool connected;
  final List<dynamic> events;
  final int weekOffset;
  CalendarState({this.connected = false, this.events = const [], this.weekOffset = 0});
}

/// Riverpod notifier that owns the user's Google Calendar connection and a
/// rolling window of events. The window is pre-fetched wide (12 months
/// back, 24 months forward) so month-view scrubbing and week-view offset
/// changes don't have to hit the API — only explicit create/delete or a
/// `weekOffset` jump outside the window refetches.
class CalendarNotifier extends StateNotifier<CalendarState> {
  final CalendarService service;

  CalendarNotifier(this.service) : super(CalendarState()) {
    checkStatus();
  }

  Future<void> checkStatus() async {
    final connected = await service.isConnected();
    state = CalendarState(connected: connected, events: state.events, weekOffset: state.weekOffset);
    if (connected) await fetchEvents();
  }

  Future<void> connect() async {
    final ok = await service.connect();
    if (ok) await checkStatus();
  }

  Future<void> disconnect() async {
    await service.disconnect();
    state = CalendarState(connected: false);
  }

  Future<void> fetchEvents({int monthOffset = 0}) async {
    final now = DateTime.now();
    // Fetch 12 months back, 24 months forward
    final rangeStart = DateTime(now.year, now.month - 12, 1);
    final rangeEnd = DateTime(now.year, now.month + 25, 1);
    // Also include the week view range
    final startOfWeek = now.subtract(Duration(days: now.weekday % 7)).add(Duration(days: state.weekOffset * 7));
    final weekStart = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
    final weekEnd = weekStart.add(const Duration(days: 7));
    final start = weekStart.isBefore(rangeStart) ? weekStart : rangeStart;
    final end = weekEnd.isAfter(rangeEnd) ? weekEnd : rangeEnd;
    final events = await service.getEvents(timeMin: start, timeMax: end);
    state = CalendarState(connected: true, events: events, weekOffset: state.weekOffset);
  }

  Future<void> setWeekOffset(int offset) async {
    state = CalendarState(connected: state.connected, events: state.events, weekOffset: offset);
    await fetchEvents();
  }

  Future<void> createEvent({
    required String summary,
    required String start,
    required String end,
    bool allDay = false,
  }) async {
    await service.createEvent(summary: summary, start: start, end: end, allDay: allDay);
    await fetchEvents();
  }

  Future<void> deleteEvent(String eventId) async {
    await service.deleteEvent(eventId);
    await fetchEvents();
  }
}

final calendarServiceProvider = Provider<CalendarService>((ref) {
  final db = ref.watch(databaseProvider);
  return CalendarService(db);
});

final calendarProvider = StateNotifierProvider<CalendarNotifier, CalendarState>((ref) {
  final service = ref.watch(calendarServiceProvider);
  return CalendarNotifier(service);
});
