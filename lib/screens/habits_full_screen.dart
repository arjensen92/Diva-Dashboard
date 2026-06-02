import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_colors.dart';
import '../widgets/full_screen_overlay.dart';
import '../providers/habits_provider.dart';

Color _parseColor(String hex) => Color(int.parse(hex.replaceFirst('#', '0xFF')));

class HabitsFullScreen extends ConsumerStatefulWidget {
  const HabitsFullScreen({super.key});
  @override
  ConsumerState<HabitsFullScreen> createState() => _HabitsFullScreenState();
}

class _HabitsFullScreenState extends ConsumerState<HabitsFullScreen> {
  int _viewDays = 28;

  void _showAddDialog() {
    final nameController = TextEditingController();
    final targetController = TextEditingController(text: '1');
    final unitController = TextEditingController();
    String type = 'boolean';
    String color = '#6366f1';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppColors.radius)),
          title: const Text('New Habit'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(hintText: 'e.g. Exercise, Read, Drink water'),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                DropdownButton<String>(
                  value: type,
                  isExpanded: true,
                  dropdownColor: AppColors.surface,
                  items: const [
                    DropdownMenuItem(value: 'boolean', child: Text('Yes / No (checkbox)')),
                    DropdownMenuItem(value: 'numeric', child: Text('Numeric (count toward goal)')),
                  ],
                  onChanged: (v) => setDialogState(() => type = v ?? 'boolean'),
                ),
                if (type == 'numeric') ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: targetController,
                          decoration: const InputDecoration(labelText: 'Daily Target'),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: unitController,
                          decoration: const InputDecoration(labelText: 'Unit'),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                const Text('Color', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: ['#6366f1', '#22c55e', '#f59e0b', '#ef4444', '#ec4899', '#06b6d4', '#8b5cf6'].map((c) {
                    return GestureDetector(
                      onTap: () => setDialogState(() => color = c),
                      child: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: _parseColor(c),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: color == c ? Colors.white : Colors.transparent, width: 3),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                print('[Habits] Add pressed, name: "$name"');
                if (name.isNotEmpty) {
                  ref.read(habitsProvider.notifier).addHabit(
                    name: name,
                    type: type,
                    target: double.tryParse(targetController.text) ?? 1,
                    unit: unitController.text.trim(),
                    color: color,
                  );
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Add Habit'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(habitsProvider);

    // Generate date columns
    final dates = <String>[];
    for (int i = _viewDays - 1; i >= 0; i--) {
      final d = DateTime.now().subtract(Duration(days: i));
      dates.add('${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
    }

    return FullScreenOverlay(
      title: 'Habits',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top bar
          Wrap(
            spacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: _showAddDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New Habit'),
              ),
              ToggleButtons(
                isSelected: [_viewDays == 7, _viewDays == 28],
                onPressed: (i) => setState(() => _viewDays = i == 0 ? 7 : 28),
                borderRadius: BorderRadius.circular(AppColors.radiusSm),
                selectedColor: Colors.white,
                fillColor: AppColors.accent,
                color: AppColors.textMuted,
                constraints: const BoxConstraints(minHeight: 36, minWidth: 50),
                children: const [Text('7d'), Text('28d')],
              ),
            ],
          ),
          const SizedBox(height: 24),

          if (state.habits.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.check_circle_outline, size: 40, color: AppColors.textMuted),
                    SizedBox(height: 8),
                    Text('No habits yet. Add your first!', style: TextStyle(color: AppColors.textMuted)),
                  ],
                ),
              ),
            ),

          ...state.habits.map((habit) {
            final color = _parseColor(habit.color);
            final streak = ref.read(habitsProvider.notifier).getStreak(habit);

            return Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
                      const SizedBox(width: 8),
                      Expanded(child: Text(habit.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                      if (habit.type == 'numeric')
                        Text('Goal: ${habit.target.toInt()} ${habit.unit}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                      if (streak > 0) ...[
                        const SizedBox(width: 8),
                        Text('${streak}d streak', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                      ],
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () => ref.read(habitsProvider.notifier).deleteHabit(habit.id),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.red,
                          side: BorderSide(color: AppColors.red.withValues(alpha: 0.3)),
                          minimumSize: const Size(60, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                        ),
                        child: const Text('Delete', style: TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Heatmap grid
                  GridView.count(
                    crossAxisCount: 7,
                    mainAxisSpacing: 3,
                    crossAxisSpacing: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: dates.map((date) {
                      final key = '${habit.id}_$date';
                      final val = state.logs[key] ?? 0;
                      int level = 0;
                      if (habit.type == 'boolean') {
                        level = val >= 1 ? 4 : 0;
                      } else {
                        final pct = val / habit.target;
                        if (pct > 0) level = (pct * 4).ceil().clamp(1, 4);
                      }
                      return GestureDetector(
                        onTap: () => ref.read(habitsProvider.notifier).toggleLog(habit, date),
                        child: Tooltip(
                          message: '$date: ${val.toInt()}${habit.unit.isNotEmpty ? ' ${habit.unit}' : ''}',
                          child: Container(
                            decoration: BoxDecoration(
                              color: level > 0 ? color.withValues(alpha: level * 0.25) : AppColors.surfaceHover,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
