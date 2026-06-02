import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import '../providers/calendar_provider.dart';
import '../providers/tasks_provider.dart';

/// A row item rendered inside a day column. Encapsulates both Google
/// Calendar events and locally-stored tasks-with-due-dates so the view
/// doesn't have to special-case the two sources during layout.
class _DayItem {
  final String title;
  final String time; // 'All day' or formatted time
  final bool strike; // line-through (completed tasks)
  final bool isTask; // colored differently from Google events
  final Map<String, dynamic>? sourceEvent; // for onEventTap on Google rows

  const _DayItem({
    required this.title,
    required this.time,
    this.strike = false,
    this.isTask = false,
    this.sourceEvent,
  });
}

/// Shared week calendar grid used in both card view and full screen.
/// [compact] shrinks fonts/padding for the dashboard card.
/// [onEventTap] opens event detail in full screen mode.
class WeekView extends ConsumerWidget {
  final bool compact;
  final void Function(Map<String, dynamic> event)? onEventTap;

  const WeekView({super.key, this.compact = false, this.onEventTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(calendarProvider);
    final dueTasks = ref.watch(dueTasksProvider).value ?? const [];
    final now = DateTime.now();
    final startOfWeek = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday % 7))
        .add(Duration(days: state.weekOffset * 7));
    final days = List.generate(7, (i) => startOfWeek.add(Duration(days: i)));
    final todayStr = DateFormat('yyyy-MM-dd').format(now);
    final dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: days.map((day) {
        final dayStr = DateFormat('yyyy-MM-dd').format(day);
        final isToday = dayStr == todayStr;

        // Merge Google events + local tasks for this day into one list.
        final items = <_DayItem>[];
        for (final e in state.events) {
          final start = e['start']?['dateTime'] ?? e['start']?['date'] ?? '';
          if (!start.toString().startsWith(dayStr)) continue;
          final isAllDay = e['start']?['date'] != null;
          items.add(_DayItem(
            title: e['summary'] ?? '(No title)',
            time: isAllDay
                ? 'All day'
                : DateFormat.jm()
                    .format(DateTime.parse(e['start']['dateTime'])),
            sourceEvent: e,
          ));
        }
        for (final task in dueTasks) {
          final raw = task.dueDate;
          if (raw == null || raw.length < 10) continue;
          if (!raw.startsWith(dayStr)) continue;
          final hasTime = raw.length > 10;
          String timeStr = 'All day';
          if (hasTime) {
            final parsed = DateTime.tryParse(raw);
            if (parsed != null) timeStr = DateFormat.jm().format(parsed);
          }
          items.add(_DayItem(
            title: task.title,
            time: timeStr,
            strike: task.completed,
            isTask: true,
          ));
        }

        return Expanded(
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: compact ? 2 : 4),
            child: Column(
              children: [
                // Day header
                Container(
                  padding: EdgeInsets.symmetric(vertical: compact ? 4 : 8),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: isToday ? AppColors.accent : AppColors.border,
                        width: isToday ? 2 : 1,
                      ),
                    ),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        Text(
                          dayNames[day.weekday % 7],
                          style: TextStyle(
                            fontSize: compact ? 10 : 13,
                            fontWeight: FontWeight.w600,
                            color: isToday
                                ? AppColors.accent
                                : AppColors.textMuted,
                            shadows: AppColors.textShadow,
                          ),
                        ),
                        Text(
                          '${day.day}',
                          style: TextStyle(
                            fontSize: compact ? 14 : 18,
                            fontWeight: FontWeight.w700,
                            color: isToday ? AppColors.accent : AppColors.text,
                            shadows: AppColors.textShadow,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Events + tasks
                Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.only(top: compact ? 2 : 4),
                    itemCount: items.length,
                    physics: const BouncingScrollPhysics(),
                    itemBuilder: (_, i) {
                      final item = items[i];
                      // Tasks use a green accent + line-through for done;
                      // Google events keep the original purple-accent look.
                      final accent =
                          item.isTask ? AppColors.green : AppColors.accent;
                      return GestureDetector(
                        onTap: !item.isTask &&
                                onEventTap != null &&
                                item.sourceEvent != null
                            ? () => onEventTap!(item.sourceEvent!)
                            : null,
                        child: Container(
                          margin: EdgeInsets.only(bottom: compact ? 3 : 6),
                          padding: EdgeInsets.all(compact ? 4 : 8),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(
                                compact ? 6 : AppColors.radiusSm),
                            border: Border(
                              left: BorderSide(color: accent, width: 3),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                style: TextStyle(
                                  fontSize: compact ? 10 : 13,
                                  shadows: AppColors.textShadow,
                                  decoration: item.strike
                                      ? TextDecoration.lineThrough
                                      : null,
                                  decorationThickness: 2,
                                  color: item.strike
                                      ? AppColors.textMuted
                                      : AppColors.text,
                                ),
                                maxLines: compact ? 1 : 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                item.time,
                                style: TextStyle(
                                  fontSize: compact ? 9 : 11,
                                  color: AppColors.textMuted,
                                  shadows: AppColors.textShadow,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
