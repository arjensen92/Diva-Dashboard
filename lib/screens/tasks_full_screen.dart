import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../database/database.dart';
import '../theme/app_colors.dart';
import '../widgets/full_screen_overlay.dart';
import '../widgets/win95.dart';
import '../providers/tasks_provider.dart';

class TasksFullScreen extends ConsumerStatefulWidget {
  const TasksFullScreen({super.key});
  @override
  ConsumerState<TasksFullScreen> createState() => _TasksFullScreenState();
}

class _TasksFullScreenState extends ConsumerState<TasksFullScreen> {
  final _titleController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  /// Tap on the Add button. With text in the field: quick-add (no due
  /// date). With the field empty: open the full Win95 edit dialog so
  /// the user can set a name + optional due date in one pass.
  Future<void> _onAddPressed() async {
    final title = _titleController.text.trim();
    if (title.isNotEmpty) {
      await ref.read(listsProvider.notifier).addTask(title);
      _titleController.clear();
      return;
    }
    final result = await showTaskEditDialog(context);
    if (result == null) return;
    await ref
        .read(listsProvider.notifier)
        .addTask(result.title, dueDate: result.dueDate);
  }

  Future<void> _editTask(Task task) async {
    final result = await showTaskEditDialog(
      context,
      initialTitle: task.title,
      initialDueDate: task.dueDate,
      isEdit: true,
    );
    if (result == null) return;
    await ref.read(listsProvider.notifier).updateTaskFields(
          task.id,
          title: result.title,
          dueDate: result.dueDate,
        );
  }

  Future<void> _promptNewList() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New list'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'List name'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await ref.read(listsProvider.notifier).addList(name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(listsProvider);
    final activeTasks = state.tasks;
    final completedTasks = state.recentlyCompleted;

    return FullScreenOverlay(
      title: 'Lists',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // List selector tabs — horizontally scrollable, with a "+" at the end
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ...state.availableLists.map((listName) {
                  final isActive = state.activeList == listName;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () => ref.read(listsProvider.notifier).setActiveList(listName),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isActive ? AppColors.accent : Colors.transparent,
                          borderRadius: BorderRadius.circular(AppColors.radiusSm),
                          border: Border.all(color: isActive ? AppColors.accent : AppColors.border),
                        ),
                        child: Text(
                          listName,
                          style: TextStyle(
                            fontFamily: 'PressStart2P',
                            fontSize: 11,
                            color: isActive ? Colors.white : AppColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                GestureDetector(
                  onTap: _promptNewList,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppColors.radiusSm),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Icon(Icons.add, size: 16, color: AppColors.textMuted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Add item form
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _titleController,
                  decoration: InputDecoration(hintText: 'Add to ${state.activeList}...'),
                  onSubmitted: (_) => _onAddPressed(),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(AppColors.radiusSm),
                child: InkWell(
                  onTap: _onAddPressed,
                  borderRadius: BorderRadius.circular(AppColors.radiusSm),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    child: Text('Add', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Active items
          if (activeTasks.isEmpty && completedTasks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.checklist, size: 40, color: AppColors.textMuted),
                    SizedBox(height: 8),
                    Text('No items', style: TextStyle(color: AppColors.textMuted)),
                  ],
                ),
              ),
            )
          else ...[
            ...activeTasks.map((task) => _TaskTile(
                  task: task,
                  onToggle: () =>
                      ref.read(listsProvider.notifier).toggleTask(task),
                  onEdit: () => _editTask(task),
                  onDelete: () =>
                      ref.read(listsProvider.notifier).deleteTask(task.id),
                )),
            // Completed tail
            if (completedTasks.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  'COMPLETED',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              ...completedTasks.map((task) => _TaskTile(
                    task: task,
                    onToggle: () =>
                        ref.read(listsProvider.notifier).toggleTask(task),
                    onEdit: () => _editTask(task),
                    onDelete: () =>
                        ref.read(listsProvider.notifier).deleteTask(task.id),
                  )),
            ],
          ],
        ],
      ),
    );
  }
}

/// Single task row in the full-screen Lists view. Checkbox, title
/// (strikethrough when complete), optional due-date chip, plus pencil
/// (edit) and × (delete) buttons. The pencil opens [showTaskEditDialog]
/// — same dialog the empty-field "Add" path uses, so name + due date
/// edits route through one UI.
class _TaskTile extends StatelessWidget {
  final Task task;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _TaskTile({
    required this.task,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onToggle,
            child: Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: task.completed ? AppColors.green : Colors.transparent,
                border: Border.all(
                    color:
                        task.completed ? AppColors.green : AppColors.border,
                    width: 2),
              ),
              child: task.completed
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: TextStyle(
                    fontSize: 15,
                    decoration: task.completed
                        ? TextDecoration.lineThrough
                        : null,
                    color: task.completed
                        ? AppColors.textMuted
                        : AppColors.text,
                  ),
                ),
                if (task.dueDate != null && task.dueDate!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _DueDateChip(
                        dueDate: task.dueDate!, onTap: onEdit),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit',
            onPressed: onEdit,
            icon: const Icon(Icons.edit, size: 18, color: AppColors.accent),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: onDelete,
            icon: const Icon(Icons.close, size: 18, color: AppColors.red),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          ),
        ],
      ),
    );
  }
}

class _DueDateChip extends StatelessWidget {
  final String dueDate;
  final VoidCallback onTap;
  const _DueDateChip({required this.dueDate, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final parsed = DateTime.tryParse(dueDate);
    String label = dueDate;
    if (parsed != null) {
      final hasTime = dueDate.length > 10;
      label = hasTime
          ? '${DateFormat.MMMd().format(parsed)} ${DateFormat.jm().format(parsed)}'
          : DateFormat.MMMd().format(parsed);
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.event, size: 12, color: AppColors.accent),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// Win95 task add/edit dialog
// =====================================================================

/// Result of [showTaskEditDialog]. Returned via Navigator.pop. The
/// caller decides whether to insert or update based on context.
class TaskEditResult {
  final String title;
  final String? dueDate;
  const TaskEditResult({required this.title, this.dueDate});
}

/// Opens a Win95-styled modal for entering or editing a task. Returns
/// null if the user cancels. With [initialTitle] / [initialDueDate]
/// pre-populated and [isEdit] true, the dialog title and primary button
/// switch to "Edit item" / "Save". Used both by the empty-field "Add"
/// fallback in the full-screen Lists view and by the per-row pencil
/// button.
Future<TaskEditResult?> showTaskEditDialog(
  BuildContext context, {
  String initialTitle = '',
  String? initialDueDate,
  bool isEdit = false,
}) {
  return showDialog<TaskEditResult>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _TaskEditDialog(
      initialTitle: initialTitle,
      initialDueDate: initialDueDate,
      isEdit: isEdit,
    ),
  );
}

class _TaskEditDialog extends StatefulWidget {
  final String initialTitle;
  final String? initialDueDate;
  final bool isEdit;
  const _TaskEditDialog({
    required this.initialTitle,
    required this.initialDueDate,
    required this.isEdit,
  });

  @override
  State<_TaskEditDialog> createState() => _TaskEditDialogState();
}

class _TaskEditDialogState extends State<_TaskEditDialog> {
  late final TextEditingController _titleCtrl;
  String? _dueDate;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.initialTitle);
    _dueDate = widget.initialDueDate;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final existing = _dueDate;
    DateTime initialDate = DateTime.now();
    TimeOfDay? initialTime;
    if (existing != null && existing.isNotEmpty) {
      final parsed = DateTime.tryParse(existing);
      if (parsed != null) {
        initialDate = parsed;
        if (existing.length > 10) {
          initialTime = TimeOfDay(hour: parsed.hour, minute: parsed.minute);
        }
      }
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: initialTime ?? const TimeOfDay(hour: 9, minute: 0),
    );
    final dateStr =
        '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    setState(() {
      _dueDate = time == null
          ? dateStr
          : '${dateStr}T${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    });
  }

  void _clearDueDate() => setState(() => _dueDate = null);

  void _submit() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    Navigator.of(context).pop(
      TaskEditResult(title: title, dueDate: _dueDate),
    );
  }

  String _formatDueDate(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final hasTime = raw.length > 10;
    return hasTime
        ? '${DateFormat.MMMMd().format(parsed)} • ${DateFormat.jm().format(parsed)}'
        : DateFormat.MMMMd().format(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      insetPadding: const EdgeInsets.all(40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Win95Panel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Win95TitleBar(
                title: widget.isEdit ? 'Edit item' : 'New item',
                titleFontSize: 14,
                buttonSize: 22,
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                leading: const Icon(Icons.checklist,
                    size: 14, color: Colors.white),
                onClose: () => Navigator.of(context).pop(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Name',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Win95.sunkenBorder(width: 1.5),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      child: TextField(
                        controller: _titleCtrl,
                        autofocus: true,
                        style: const TextStyle(
                            fontSize: 14, color: Colors.black),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'Item name…',
                          hintStyle: TextStyle(color: Colors.black38),
                        ),
                        onSubmitted: (_) => _submit(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Due date',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (_dueDate == null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Win95Button(
                          onTap: _pickDueDate,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.event,
                                  size: 14, color: Colors.black87),
                              SizedBox(width: 6),
                              Text('Add due date',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.black87)),
                            ],
                          ),
                        ),
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: Win95Button(
                              onTap: _pickDueDate,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.event,
                                      size: 14, color: Colors.black87),
                                  const SizedBox(width: 6),
                                  Text(
                                    _formatDueDate(_dueDate!),
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.black87),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Win95Button(
                            onTap: _clearDueDate,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            child: const Text('Clear',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.black87)),
                          ),
                        ],
                      ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Win95Button(
                          onTap: () => Navigator.of(context).pop(),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 6),
                          child: const Text('Cancel',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.black87)),
                        ),
                        const SizedBox(width: 8),
                        Win95Button(
                          onTap: _submit,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 6),
                          child: Text(
                            widget.isEdit ? 'Save' : 'Create',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black87,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
