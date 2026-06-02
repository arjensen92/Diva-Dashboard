import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/database.dart';
import '../main.dart';
import '../services/lists_service.dart';

/// State for the active list view: every active task in [tasks], plus a
/// rolling tail of the most-recently-completed tasks in
/// [recentlyCompleted] (capped at [completedTailLimit], ordered newest
/// first). Splitting them lets the card render them as two sections.
class ListsState {
  final List<Task> tasks;
  final List<Task> recentlyCompleted;
  final String filter;
  final String activeList;
  final List<String> availableLists;
  ListsState({
    required this.tasks,
    this.recentlyCompleted = const [],
    this.filter = 'active',
    this.activeList = '',
    this.availableLists = const [],
  });
}

class ListsNotifier extends StateNotifier<ListsState> {
  final AppDatabase db;

  /// Max number of completed tasks shown in the "Recently completed" tail.
  static const int completedTailLimit = 6;

  ListsNotifier(this.db) : super(ListsState(tasks: [])) {
    _init();
  }

  Future<void> _init() async {
    final lists = await ListsService.load();
    state = ListsState(
      tasks: state.tasks,
      recentlyCompleted: state.recentlyCompleted,
      filter: state.filter,
      activeList: lists.isNotEmpty ? lists.first : '',
      availableLists: lists,
    );
    await fetchTasks();
  }

  Future<void> fetchTasks() async {
    if (state.activeList.isEmpty) {
      state = ListsState(
        tasks: [],
        filter: state.filter,
        activeList: state.activeList,
        availableLists: state.availableLists,
      );
      return;
    }
    // Pull both active and recently-completed in one shot — every task
    // in the active list, then split client-side. This is cheaper than
    // two queries when the list is small (typical case) and keeps the
    // ordering logic in one place.
    final all = await db.getTasks(filter: 'all', listName: state.activeList);
    final active = all.where((t) => !t.completed).toList();
    final completed = all.where((t) => t.completed).toList();
    // Sort completed by completedAt desc; null completedAt sinks to the
    // bottom (legacy rows from before the column existed).
    completed.sort((a, b) {
      final aAt = a.completedAt?.millisecondsSinceEpoch ?? 0;
      final bAt = b.completedAt?.millisecondsSinceEpoch ?? 0;
      return bAt.compareTo(aAt);
    });
    state = ListsState(
      tasks: active,
      recentlyCompleted: completed.take(completedTailLimit).toList(),
      filter: state.filter,
      activeList: state.activeList,
      availableLists: state.availableLists,
    );
  }

  Future<void> setFilter(String filter) async {
    state = ListsState(
      tasks: state.tasks,
      recentlyCompleted: state.recentlyCompleted,
      filter: filter,
      activeList: state.activeList,
      availableLists: state.availableLists,
    );
    await fetchTasks();
  }

  Future<void> setActiveList(String listName) async {
    state = ListsState(
      tasks: state.tasks,
      recentlyCompleted: state.recentlyCompleted,
      filter: state.filter,
      activeList: listName,
      availableLists: state.availableLists,
    );
    await fetchTasks();
  }

  Future<void> addList(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    if (state.availableLists.contains(trimmed)) {
      await setActiveList(trimmed);
      return;
    }
    final newLists = [...state.availableLists, trimmed];
    await ListsService.save(newLists);
    state = ListsState(
      tasks: state.tasks,
      recentlyCompleted: state.recentlyCompleted,
      filter: state.filter,
      activeList: trimmed,
      availableLists: newLists,
    );
    await fetchTasks();
  }

  Future<void> addTask(String title, {String? dueDate}) async {
    if (state.activeList.isEmpty) return;
    final maxOrder = state.tasks.isEmpty
        ? 0
        : state.tasks.map((t) => t.sortOrder).reduce((a, b) => a > b ? a : b);
    await db.insertTask(TasksCompanion.insert(
      title: title,
      listName: Value(state.activeList),
      sortOrder: Value(maxOrder + 1),
      dueDate: Value(dueDate),
    ));
    await fetchTasks();
  }

  /// Replaces the title and due date of [taskId] in one call. Used by
  /// the edit dialog where the user supplies a complete (title, dueDate)
  /// pair. Pass `dueDate: null` to clear the existing due date.
  Future<void> updateTaskFields(
    int taskId, {
    required String title,
    String? dueDate,
  }) async {
    await db.updateTask(
      taskId,
      TasksCompanion(
        title: Value(title),
        dueDate: Value(dueDate),
      ),
    );
    await fetchTasks();
  }

  /// Toggle complete/incomplete. On completion, stamps `completedAt` so
  /// the task takes the top slot of the recently-completed tail. On
  /// uncomplete (clicking a completed task to send it back), clears
  /// `completedAt`.
  Future<void> toggleTask(Task task) async {
    final isCompleting = !task.completed;
    await db.updateTask(
      task.id,
      TasksCompanion(
        completed: Value(isCompleting),
        completedAt: Value(isCompleting ? DateTime.now() : null),
      ),
    );
    await fetchTasks();
  }

  /// Sets or clears the optional [dueDate] on a task. Pass null to
  /// remove. The string format is `YYYY-MM-DD` for date-only or
  /// `YYYY-MM-DDTHH:mm` when a specific time was picked.
  Future<void> setDueDate(int taskId, String? dueDate) async {
    await db.updateTask(taskId, TasksCompanion(dueDate: Value(dueDate)));
    await fetchTasks();
  }

  Future<void> deleteTask(int id) async {
    await db.deleteTask(id);
    await fetchTasks();
  }
}

final listsProvider = StateNotifierProvider<ListsNotifier, ListsState>((ref) {
  final db = ref.watch(databaseProvider);
  return ListsNotifier(db);
});

/// Reactive stream of every task with a `dueDate` set, across every list.
/// Calendar views watch this to merge tasks-as-events into the grid
/// alongside Google Calendar events.
final dueTasksProvider = StreamProvider<List<Task>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchTasksWithDueDate();
});
