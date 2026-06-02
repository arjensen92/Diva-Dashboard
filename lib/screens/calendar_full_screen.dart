import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import '../theme/animated_backgrounds.dart';
import '../widgets/full_screen_overlay.dart';
import '../widgets/week_view.dart';
import '../providers/calendar_provider.dart';
import 'dashboard_screen.dart';
import '../widgets/oauth_setup_dialog.dart';
import '../widgets/sparkle_overlay.dart';
import '../widgets/win95.dart';

class CalendarFullScreen extends ConsumerStatefulWidget {
  const CalendarFullScreen({super.key});
  @override
  ConsumerState<CalendarFullScreen> createState() => _CalendarFullScreenState();
}

class _CalendarFullScreenState extends ConsumerState<CalendarFullScreen> {
  void _showAddDialog() {
    String summary = '';
    DateTime selectedDate = DateTime.now();
    TimeOfDay startTime = TimeOfDay.now();
    TimeOfDay endTime = TimeOfDay(hour: TimeOfDay.now().hour + 1, minute: TimeOfDay.now().minute);
    bool allDay = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppColors.radius)),
          title: const Text('New Event'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  decoration: const InputDecoration(hintText: 'Event title'),
                  onChanged: (v) => summary = v,
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: selectedDate,
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (d != null) setDialogState(() => selectedDate = d);
                  },
                  child: Text('Date: ${DateFormat.yMMMd().format(selectedDate)}'),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: allDay,
                  onChanged: (v) => setDialogState(() => allDay = v ?? false),
                  title: const Text('All day'),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                if (!allDay) ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final t = await showTimePicker(context: ctx, initialTime: startTime);
                            if (t != null) setDialogState(() => startTime = t);
                          },
                          child: Text('Start: ${startTime.format(ctx)}'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final t = await showTimePicker(context: ctx, initialTime: endTime);
                            if (t != null) setDialogState(() => endTime = t);
                          },
                          child: Text('End: ${endTime.format(ctx)}'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (summary.isEmpty) return;
                if (allDay) {
                  final dateStr = DateFormat('yyyy-MM-dd').format(selectedDate);
                  final endDateStr = DateFormat('yyyy-MM-dd').format(selectedDate.add(const Duration(days: 1)));
                  ref.read(calendarProvider.notifier).createEvent(summary: summary, start: dateStr, end: endDateStr, allDay: true);
                } else {
                  final startDt = DateTime(selectedDate.year, selectedDate.month, selectedDate.day, startTime.hour, startTime.minute);
                  final endDt = DateTime(selectedDate.year, selectedDate.month, selectedDate.day, endTime.hour, endTime.minute);
                  ref.read(calendarProvider.notifier).createEvent(
                    summary: summary,
                    start: startDt.toUtc().toIso8601String(),
                    end: endDt.toUtc().toIso8601String(),
                  );
                }
                Navigator.pop(ctx);
              },
              child: const Text('Add Event'),
            ),
          ],
        ),
      ),
    );
  }

  void _onEventTap(Map<String, dynamic> event) {
    final eventId = event['id'];
    final summary = event['summary'] ?? '(No title)';
    final description = event['description'] ?? '';
    final isAllDay = event['start']?['date'] != null;
    String startStr = '';
    String endStr = '';
    if (isAllDay) {
      startStr = event['start']['date'] ?? '';
    } else if (event['start']?['dateTime'] != null) {
      startStr = DateFormat.yMMMd().add_jm().format(DateTime.parse(event['start']['dateTime']).toLocal());
    }
    if (!isAllDay && event['end']?['dateTime'] != null) {
      endStr = DateFormat.jm().format(DateTime.parse(event['end']['dateTime']).toLocal());
    }
    final location = event['location'] ?? '';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppColors.radius)),
        title: Text(summary, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Time
              Row(
                children: [
                  const Icon(Icons.access_time, size: 18, color: AppColors.textMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isAllDay ? 'All day · $startStr' : '$startStr – $endStr',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
              // Location
              if (location.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.location_on, size: 18, color: AppColors.textMuted),
                    const SizedBox(width: 8),
                    Expanded(child: Text(location, style: const TextStyle(fontSize: 14))),
                  ],
                ),
              ],
              // Description
              if (description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.notes, size: 18, color: AppColors.textMuted),
                    const SizedBox(width: 8),
                    Expanded(child: Text(description, style: const TextStyle(fontSize: 14))),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (eventId != null)
            TextButton(
              onPressed: () {
                ref.read(calendarProvider.notifier).deleteEvent(eventId);
                Navigator.pop(ctx);
              },
              child: const Text('Delete', style: TextStyle(color: AppColors.red)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(calendarProvider);

    if (!state.connected) {
      return FullScreenOverlay(
        title: 'Calendar',
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.calendar_today, size: 60, color: AppColors.textMuted),
              const SizedBox(height: 16),
              const Text('Connect your Google Calendar', style: TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  // If the .env hasn't been populated with Google OAuth
                  // credentials, connect() bails silently. Surface a
                  // setup-required dialog instead so the user knows
                  // what to do rather than seeing a dead button.
                  final svc =
                      ref.read(calendarProvider.notifier).service;
                  if (!svc.isConfigured) {
                    await showOAuthSetupRequiredDialog(
                      context,
                      serviceName: 'Google Calendar',
                      envVarNames: const [
                        'GOOGLE_CLIENT_ID',
                        'GOOGLE_CLIENT_SECRET',
                      ],
                      credentialUrl:
                          'https://console.cloud.google.com/apis/credentials  (OAuth 2.0 Client ID, Desktop app type, '
                          'add http://127.0.0.1:8889/callback as a redirect URI)',
                      credentialUrlLabel:
                          'Google Cloud Console for Calendar API OAuth setup',
                    );
                    return;
                  }
                  ref.read(calendarProvider.notifier).connect();
                },
                child: const Text('Connect Google Calendar'),
              ),
            ],
          ),
        ),
      );
    }

    final theme = ref.watch(themeProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedBackground(
        theme: theme,
        child: Stack(
          children: [
            const SparkleOverlay(),
            Column(
          children: [
            Win95TitleBar(
              title: 'Calendar',
              titleFontSize: 16,
              buttonSize: 44,
              onClose: () => Navigator.of(context).pop(),
            ),
            // Controls bar below title
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: Win95.gray,
              child: Row(
                children: [
                  OutlinedButton(
                    onPressed: () => ref.read(calendarProvider.notifier).setWeekOffset(state.weekOffset - 1),
                    child: const Icon(Icons.chevron_left, size: 20),
                  ),
                  const SizedBox(width: 4),
                  OutlinedButton(
                    onPressed: () => ref.read(calendarProvider.notifier).setWeekOffset(0),
                    child: const Text('Today', style: TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(width: 4),
                  OutlinedButton(
                    onPressed: () => ref.read(calendarProvider.notifier).setWeekOffset(state.weekOffset + 1),
                    child: const Icon(Icons.chevron_right, size: 20),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _showAddDialog,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Event'),
                  ),
                ],
              ),
          ),
            // Week grid — fills remaining space
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: WeekView(onEventTap: _onEventTap),
                ),
              ),
            ],
          ),
        ]),
      ),
    );
  }
}
