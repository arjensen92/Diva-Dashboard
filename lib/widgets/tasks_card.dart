import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math' as math;
import '../database/database.dart';
import '../theme/app_colors.dart';
import '../providers/tasks_provider.dart';

/// Dashboard tile for the Lists feature. Shows the list tabs at the top,
/// then the active items, then a "Completed" section at the bottom
/// listing the most-recently-completed tasks (newest first, max 6).
/// Tapping an active item completes it (sends it to the bottom);
/// tapping a completed item un-completes it (sends it back up).
class TasksCardContent extends ConsumerWidget {
  const TasksCardContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(listsProvider);

    // Card has limited vertical space — share it between the active and
    // completed sections. Active gets up to 6 rows, completed up to 4.
    const activeMax = 6;
    const completedMax = 4;
    final activeTasks = state.tasks.take(activeMax).toList();
    final completedTasks = state.recentlyCompleted.take(completedMax).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // List tabs
        Row(
          children: state.availableLists.map((listName) {
            final isActive = state.activeList == listName;
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: GestureDetector(
                onTap: () =>
                    ref.read(listsProvider.notifier).setActiveList(listName),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppColors.accent.withValues(alpha: 0.3)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color:
                            isActive ? AppColors.accent : AppColors.border),
                  ),
                  child: Text(
                    listName,
                    style: TextStyle(
                      fontFamily: 'PressStart2P',
                      fontSize: 11,
                      color: isActive ? AppColors.accent : AppColors.textMuted,
                      shadows: AppColors.textShadow,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: (activeTasks.isEmpty && completedTasks.isEmpty)
              ? const Center(
                  child: Text(
                    'No items',
                    style: TextStyle(
                        fontFamily: 'PressStart2P',
                        fontSize: 14,
                        color: AppColors.textMuted,
                        shadows: AppColors.textShadow),
                  ),
                )
              : ListView(
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    // Active items.
                    for (int i = 0;
                        i < math.min(activeTasks.length, activeMax);
                        i++) ...[
                      if (i > 0)
                        const Divider(color: AppColors.border, height: 1),
                      _TaskRow(
                        task: activeTasks[i],
                        onTap: () => ref
                            .read(listsProvider.notifier)
                            .toggleTask(activeTasks[i]),
                      ),
                    ],
                    // Completed tail — heading + strikethrough rows.
                    if (completedTasks.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      const Padding(
                        padding: EdgeInsets.only(top: 4, bottom: 4),
                        child: Text(
                          'Completed',
                          style: TextStyle(
                            fontFamily: 'PressStart2P',
                            fontSize: 9,
                            color: AppColors.textMuted,
                            shadows: AppColors.textShadow,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      for (int i = 0; i < completedTasks.length; i++) ...[
                        if (i > 0)
                          const Divider(
                              color: AppColors.border, height: 1),
                        _TaskRow(
                          task: completedTasks[i],
                          onTap: () => ref
                              .read(listsProvider.notifier)
                              .toggleTask(completedTasks[i]),
                        ),
                      ],
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _TaskRow extends StatelessWidget {
  final Task task;
  final VoidCallback onTap;
  const _TaskRow({required this.task, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDone = task.completed;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDone ? AppColors.green : Colors.transparent,
                border: Border.all(
                  color: isDone ? AppColors.green : AppColors.border,
                  width: 2,
                ),
              ),
              child: isDone
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                task.title,
                style: TextStyle(
                  fontFamily: 'PressStart2P',
                  fontSize: 12,
                  decoration: isDone ? TextDecoration.lineThrough : null,
                  decorationColor: AppColors.textMuted,
                  decorationThickness: 2,
                  color: isDone ? AppColors.textMuted : AppColors.text,
                  shadows: AppColors.textShadow,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
