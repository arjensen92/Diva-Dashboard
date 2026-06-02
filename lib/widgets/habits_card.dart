import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math' as math;
import '../theme/app_colors.dart';
import '../providers/habits_provider.dart';

Color _parseColor(String hex) {
  return Color(int.parse(hex.replaceFirst('#', '0xFF')));
}

class HabitsCardContent extends ConsumerWidget {
  const HabitsCardContent({super.key});

  String _today() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(habitsProvider);

    if (state.habits.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 40, color: AppColors.textMuted),
            SizedBox(height: 8),
            Text('No habits yet', style: TextStyle(fontFamily: 'PressStart2P', color: AppColors.textMuted, shadows: AppColors.textShadow)),
          ],
        ),
      );
    }

    final today = _today();

    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: math.min(state.habits.length, 6),
      separatorBuilder: (_, __) => Divider(color: AppColors.border, height: 1),
      itemBuilder: (context, i) {
        final habit = state.habits[i];
        final key = '${habit.id}_$today';
        final val = state.logs[key] ?? 0;
        final done = habit.type == 'boolean' ? val >= 1 : val >= habit.target;
        final color = _parseColor(habit.color);

        return GestureDetector(
          onTap: () => ref.read(habitsProvider.notifier).toggleLog(habit, today),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                if (habit.type == 'boolean')
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: done ? color : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: done ? color : AppColors.border, width: 2),
                    ),
                    child: done ? const Icon(Icons.check, size: 18, color: Colors.white) : null,
                  )
                else
                  SizedBox(
                    width: 32, height: 32,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: (val / habit.target).clamp(0, 1),
                          strokeWidth: 3,
                          backgroundColor: AppColors.border,
                          valueColor: AlwaysStoppedAnimation(color),
                        ),
                        Text('${val.toInt()}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, shadows: AppColors.textShadow)),
                      ],
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(child: Text(habit.name, style: const TextStyle(fontFamily: 'PressStart2P', fontSize: 10, shadows: AppColors.textShadow))),
              ],
            ),
          ),
        );
      },
    );
  }
}
