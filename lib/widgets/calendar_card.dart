import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import '../providers/calendar_provider.dart';
import '../providers/tasks_provider.dart';
import '../services/holiday_service.dart';
import '../services/path_service.dart';
import 'win95.dart';

/// One row that renders inside a calendar day cell. [title] is what's
/// displayed; [strike] applies a line-through (used for completed
/// tasks). [time] is shown elsewhere for the week view; the month view
/// just renders the title.
typedef CalendarDayEntry = ({String title, bool strike, String? time});

/// Ticks whenever the calendar day rolls over, so widgets that watch it
/// rebuild at midnight without needing the whole app to restart.
final currentDateProvider = StateNotifierProvider<_CurrentDateTicker, DateTime>((ref) {
  return _CurrentDateTicker();
});

class _CurrentDateTicker extends StateNotifier<DateTime> {
  Timer? _timer;
  _CurrentDateTicker() : super(DateTime.now()) {
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      final now = DateTime.now();
      if (now.year != state.year || now.month != state.month || now.day != state.day) {
        state = now;
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

String get _holidayIconDir => PathService.holidayIconsDir;
String get _monthIconsDir => PathService.iconsDir;

/// Small widget that bobs its child up and down by [amplitude]px with no
/// smoothing — the child snaps between y=0 and y=-amplitude every [periodMs].
class _BobbingIcon extends StatefulWidget {
  final Widget child;
  final int delayMs;
  final int amplitude;
  final int periodMs;
  const _BobbingIcon({
    required this.child,
    this.delayMs = 0,
    this.amplitude = 2,
    this.periodMs = 500,
  });

  @override
  State<_BobbingIcon> createState() => _BobbingIconState();
}

class _BobbingIconState extends State<_BobbingIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _up = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: Duration(milliseconds: widget.periodMs));
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _up = !_up);
        _controller.forward(from: 0);
      }
    });
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(0, _up ? -widget.amplitude.toDouble() : 0),
      child: widget.child,
    );
  }
}

/// Build month decoration icons in a specific order
/// Left: clouds, f1fdd, flowers | Right: bee, clouds, flowers
List<Widget> _buildMonthIcons(List<String> allPaths, {required bool left}) {
  // Find specific icons by name
  String? find(String pattern) {
    try { return allPaths.firstWhere((p) {
      final name = p.split(RegExp(r'[/\\]')).last.toLowerCase();
      return name.contains(pattern) && !name.contains('flowers-bg');
    }); } catch (_) { return null; }
  }
  final cloud = find('123g4g');
  final f1fdd = find('f1fdd');
  final flowers = find('flowers');
  final bee = find('bee');

  final paths = left
      ? [cloud, f1fdd, flowers]
      : [bee, cloud, flowers];

  return paths.where((p) => p != null).map((path) {
    final isBee = path!.toLowerCase().contains('bee');
    final isCloud = path.toLowerCase().contains('123g4g');
    final isFlowers = path.toLowerCase().contains('flowers');
    final shouldFlip = !left && (isCloud || isFlowers);
    Widget img = Image.file(File(path), width: 50, height: 50, errorBuilder: (_, __, ___) => const SizedBox.shrink());
    if (shouldFlip) {
      img = Transform.flip(flipX: true, child: img);
    }
    if (isBee) {
      img = _BobbingIcon(child: img);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: img,
    );
  }).toList();
}

/// Renders a file image stretched to cover the full parent Stack — used for
/// holidays whose decoration takes over the entire calendar day cell.
Widget stretchedImageFill(String path, {double opacity = 1.0}) {
  final img = Image.file(
    File(path),
    fit: BoxFit.cover,
    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
  );
  return Positioned.fill(
    child: opacity < 1.0 ? Opacity(opacity: opacity, child: img) : img,
  );
}

/// Pixel-art style text shadow — renders text twice, black underneath shifted by 2px
Widget _pixelShadowText(String text, TextStyle style, {int maxLines = 1, TextOverflow overflow = TextOverflow.ellipsis, bool shadow = true}) {
  if (!shadow) {
    return Text(text, style: style, maxLines: maxLines, overflow: overflow);
  }
  return Stack(
    children: [
      // Shadow — black, shifted 1px
      Text(text, style: style.copyWith(color: Colors.black, shadows: []), maxLines: maxLines, overflow: overflow),
      // Foreground — offset up-left by 1px
      Transform.translate(
        offset: const Offset(-1, -1),
        child: Text(text, style: style.copyWith(shadows: []), maxLines: maxLines, overflow: overflow),
      ),
    ],
  );
}

// Month offset provider for the card view
final calendarMonthOffsetProvider = StateProvider<int>((ref) => 0);

class CalendarCardContent extends ConsumerWidget {
  const CalendarCardContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(calendarProvider);
    final monthOffset = ref.watch(calendarMonthOffsetProvider);

    if (!state.connected) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today, size: 40, color: AppColors.textMuted),
            SizedBox(height: 8),
            Text('Connect Google Calendar', style: TextStyle(color: AppColors.textMuted, shadows: AppColors.textShadow)),
          ],
        ),
      );
    }

    // Watch so the card rebuilds when the date rolls over (midnight),
    // even if the app has been idle with no other state changes.
    final today = ref.watch(currentDateProvider);
    final now = DateTime(today.year, today.month + monthOffset, 1);
    final todayStr = DateFormat('yyyy-MM-dd').format(today);
    final firstOfMonth = DateTime(now.year, now.month, 1);
    final lastOfMonth = DateTime(now.year, now.month + 1, 0);
    final startWeekday = firstOfMonth.weekday % 7;
    final daysInMonth = lastOfMonth.day;
    final dayNames = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    // Build map of date -> list of entries. Holidays come from
    // holiday_service.dart (rendered separately below). Calendar events
    // come from the Google API; tasks-with-due-date come from the local
    // DB via dueTasksProvider — both merge into the same per-day list.
    final dueTasks = ref.watch(dueTasksProvider).value ?? const [];
    final eventsByDate = <String, List<CalendarDayEntry>>{};
    for (final e in state.events) {
      final start = e['start']?['dateTime'] ?? e['start']?['date'] ?? '';
      if (start.toString().length >= 10) {
        final dateKey = start.toString().substring(0, 10);
        eventsByDate.putIfAbsent(dateKey, () => []);
        eventsByDate[dateKey]!.add((
          title: e['summary'] ?? '(No title)',
          strike: false,
          time: null,
        ));
      }
    }
    for (final task in dueTasks) {
      final raw = task.dueDate;
      if (raw == null || raw.length < 10) continue;
      final dateKey = raw.substring(0, 10);
      eventsByDate.putIfAbsent(dateKey, () => []);
      eventsByDate[dateKey]!.add((
        title: task.title,
        strike: task.completed,
        time: null,
      ));
    }

    // Load month-specific icons
    final monthName = DateFormat.MMMM().format(now).toLowerCase();
    final monthIconDir = Directory('$_monthIconsDir/$monthName');
    final monthIcons = <String>[];
    if (monthIconDir.existsSync()) {
      for (final f in monthIconDir.listSync()) {
        if (f is File) {
          final ext = f.path.toLowerCase();
          if (ext.endsWith('.apng') || ext.endsWith('.png') || ext.endsWith('.jpg') || ext.endsWith('.gif')) {
            // Skip originals subfolder and bg files
            final fname = f.path.split(RegExp(r'[/\\]')).last.toLowerCase();
            if (!f.path.contains('originals') && !fname.contains('bg')) {
              monthIcons.add(f.path);
            }
          }
        }
      }
      // Sort so order is consistent
      monthIcons.sort();
    }

    return Column(
      children: [
        // Month header — arrows pinned, icons + title in center
        Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 12),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Center: icons + month title
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ..._buildMonthIcons(monthIcons, left: true),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: _pixelShadowText(
                          DateFormat.yMMMM().format(now),
                          TextStyle(
                            fontFamily: 'PressStart2P',
                            fontSize: 72,
                            color: monthColors[now.month],
                          ),
                        ),
                      ),
                    ),
                  ),
                  ..._buildMonthIcons(monthIcons, left: false),
                ],
              ),
              // Left arrow — pinned to left edge
              Positioned(
                left: 4,
                child: Win95Button(
                  height: 36,
                  padding: EdgeInsets.zero,
                  onTap: () => ref
                      .read(calendarMonthOffsetProvider.notifier)
                      .state = monthOffset - 1,
                  child: const SizedBox(
                    width: 36,
                    child: Center(
                      child: Text('◀',
                          style: TextStyle(fontSize: 16, color: Colors.black)),
                    ),
                  ),
                ),
              ),
              // Right arrow — pinned to right edge
              Positioned(
                right: 4,
                child: Win95Button(
                  height: 36,
                  padding: EdgeInsets.zero,
                  onTap: () => ref
                      .read(calendarMonthOffsetProvider.notifier)
                      .state = monthOffset + 1,
                  child: const SizedBox(
                    width: 36,
                    child: Center(
                      child: Text('▶',
                          style: TextStyle(fontSize: 16, color: Colors.black)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Day headers + grid with optional month background image
        Expanded(
          flex: 10,
          child: Builder(builder: (_) {
            // Find a background image — any file with "bg" in the name
            final monthDir = '$_monthIconsDir/${DateFormat.MMMM().format(now).toLowerCase()}';
            String? monthBgPath;
            final dir = Directory(monthDir);
            if (dir.existsSync()) {
              for (final f in dir.listSync()) {
                if (f is File) {
                  final name = f.path.split(RegExp(r'[/\\]')).last.toLowerCase();
                  if (name.contains('bg') && !name.contains('originals')) {
                    monthBgPath = f.path;
                    break;
                  }
                }
              }
            }

            return Stack(
              children: [
                // Month background image stretched behind everything
                if (monthBgPath != null)
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0.3,
                      child: Image.file(File(monthBgPath), fit: BoxFit.cover, alignment: Alignment.bottomCenter, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                    ),
                  ),
                Column(
                  children: [
                    // Day name headers
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: dayNames.map((d) => Expanded(
                          child: Center(
                            child: Text(d, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF333333), shadows: AppColors.textShadow)),
                          ),
                        )).toList(),
                      ),
                    ),
                    // Calendar grid
                    Expanded(
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: 1.1),
            itemCount: ((startWeekday + daysInMonth + 6) ~/ 7) * 7, // fill complete rows
            itemBuilder: (_, i) {
              // Empty cells before day 1 or after last day
              if (i < startWeekday || i >= startWeekday + daysInMonth) {
                {
                  return Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border.withValues(alpha: 0.3), width: 0.5),
                    ),
                  );
                }
                return const SizedBox.shrink();
              }
              final day = i - startWeekday + 1;
              final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
              final isToday = dateStr == todayStr;
              final events = eventsByDate[dateStr] ?? [];
              // Collect every holiday that applies today from all hardcoded
              // sources (fixed-date and computed/floating), deduplicated.
              final holidays = <String>[];
              void addHoliday(String? h) {
                if (h != null && h.isNotEmpty && !holidays.contains(h)) holidays.add(h);
              }
              holidaysFor(DateTime(now.year, now.month, day)).forEach(addHoliday);

              final monthColor = monthColors[now.month] ?? AppColors.accent;

              // First holiday with a cell background color wins.
              Color? holidayCellColor;
              for (final h in holidays) {
                final c = holidayCellColors[h];
                if (c != null) { holidayCellColor = c; break; }
              }

              // First stretched-bg holiday — rendered as full-cell art.
              String? stretchedBgPath;
              double stretchedBgOpacity = 1.0;
              for (final h in holidays) {
                if (!stretchedHolidayBgs.contains(h)) continue;
                final file = holidayIcons[h];
                if (file == null) continue;
                final p = '$_holidayIconDir\\$file';
                if (File(p).existsSync()) {
                  stretchedBgPath = p;
                  stretchedBgOpacity = stretchedHolidayOpacity[h] ?? 1.0;
                  break;
                }
              }
              // All non-stretched-bg holidays with icons — rendered side-by-side
              // at the bottom of the cell. Tracks each icon's owning holiday
              // so per-holiday effects (repeat, bob) can be applied.
              final smallIcons = <({String path, String holiday})>[];
              for (final h in holidays) {
                if (stretchedHolidayBgs.contains(h)) continue;
                final file = holidayIcons[h];
                if (file == null) continue;
                final p = '$_holidayIconDir\\$file';
                if (!File(p).existsSync()) continue;
                final repeat = holidayIconRepeat[h] ?? 1;
                for (int r = 0; r < repeat; r++) {
                  smallIcons.add((path: p, holiday: h));
                }
              }

              // Holiday cell color (e.g. Day of Pink) wins over today's tint.
              return Container(
                decoration: BoxDecoration(
                  color: holidayCellColor
                      ?? (isToday ? monthColor.withValues(alpha: 0.20) : null),
                  border: Border.all(color: AppColors.border.withValues(alpha: 0.3), width: 0.5),
                ),
                child: Stack(
                  children: [
                    // Stretched-background holiday art — covers the whole cell
                    if (stretchedBgPath != null)
                      stretchedImageFill(stretchedBgPath, opacity: stretchedBgOpacity),
                    // Small holiday icons — one per holiday, side-by-side at bottom center
                    if (smallIcons.isNotEmpty)
                      Positioned(
                        bottom: 2,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: smallIcons.map((ico) {
                            Widget img = Image.file(File(ico.path), width: 40, height: 40);
                            if (bobbingHolidays.contains(ico.holiday)) {
                              img = _BobbingIcon(amplitude: 1, child: img);
                            }
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 1),
                              child: img,
                            );
                          }).toList(),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(2),
                      child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Day number — top left, boxed
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                      decoration: BoxDecoration(
                        color: isToday ? monthColor : const Color(0xFF333333),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        '$day',
                        style: const TextStyle(
                          fontFamily: 'PressStart2P',
                          fontSize: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    // Holiday names — one line per holiday, up to 2 wrapped
                    // lines each. Some holidays (e.g. 420) are icon-only and
                    // have their name suppressed here.
                    ...holidays
                        .where((h) => !iconOnlyHolidays.contains(h))
                        .map((h) => _pixelShadowText(
                              h,
                              TextStyle(fontFamily: 'PressStart2P', fontSize: 10, color: monthColor),
                              maxLines: 2,
                            )),
                    // Event/task names — show all, wrap to 2 lines each.
                    // Switch to white when a stretched-bg holiday (e.g. Tartan
                    // Day) is drawn behind the cell — dark text is unreadable
                    // against the busy background art. Completed tasks get
                    // a line-through to mirror the lists view.
                    ...events.map((entry) => _pixelShadowText(
                      entry.title,
                      TextStyle(
                        fontFamily: 'PressStart2P',
                        fontSize: 9,
                        color: stretchedBgPath != null ? Colors.white : const Color(0xFF222222),
                        decoration: entry.strike
                            ? TextDecoration.lineThrough
                            : null,
                        decorationColor: stretchedBgPath != null
                            ? Colors.white
                            : const Color(0xFF222222),
                        decorationThickness: 2,
                      ),
                      maxLines: 2,
                      shadow: stretchedBgPath != null,
                    )),
                  ],
                ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
                  ],
                ),
              ],
            );
          }),
        ),
      ],
    );
  }
}
