import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/database.dart';
import '../main.dart';

class HabitsState {
  final List<Habit> habits;
  final Map<String, double> logs; // key: "{habitId}_{date}" -> value
  HabitsState({required this.habits, required this.logs});
}

class HabitsNotifier extends StateNotifier<HabitsState> {
  final AppDatabase db;

  HabitsNotifier(this.db) : super(HabitsState(habits: [], logs: {})) {
    fetchAll();
  }

  String _today() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> fetchAll({int days = 28}) async {
    final habits = await db.getActiveHabits();
    final end = _today();
    final startDate = DateTime.now().subtract(Duration(days: days));
    final start = '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}';
    final logList = await db.getHabitLogs(start, end);
    final logMap = <String, double>{};
    for (final l in logList) {
      logMap['${l.habitId}_${l.date}'] = l.value;
    }
    state = HabitsState(habits: habits, logs: logMap);
  }

  Future<void> toggleLog(Habit habit, String date) async {
    final key = '${habit.id}_$date';
    final current = state.logs[key] ?? 0;
    double newVal;
    if (habit.type == 'boolean') {
      newVal = current > 0 ? 0 : 1;
    } else {
      newVal = current >= habit.target ? 0 : current + 1;
    }
    await db.upsertHabitLog(habit.id, date, newVal);
    final newLogs = Map<String, double>.from(state.logs);
    newLogs[key] = newVal;
    state = HabitsState(habits: state.habits, logs: newLogs);
  }

  Future<void> addHabit({
    required String name,
    required String type,
    double target = 1,
    String unit = '',
    String color = '#6366f1',
  }) async {
    final maxOrder = state.habits.isEmpty ? 0 : state.habits.map((h) => h.sortOrder).reduce((a, b) => a > b ? a : b);
    await db.insertHabit(HabitsCompanion.insert(
      name: name,
      type: Value(type),
      target: Value(target),
      unit: Value(unit),
      color: Value(color),
      sortOrder: Value(maxOrder + 1),
    ));
    await fetchAll();
  }

  Future<void> deleteHabit(int id) async {
    await db.deleteHabit(id);
    await fetchAll();
  }

  int getStreak(Habit habit) {
    int streak = 0;
    for (int i = 0; i < 365; i++) {
      final d = DateTime.now().subtract(Duration(days: i));
      final dateStr = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final key = '${habit.id}_$dateStr';
      final val = state.logs[key] ?? 0;
      final done = habit.type == 'boolean' ? val >= 1 : val >= habit.target;
      if (done) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }
}

final habitsProvider = StateNotifierProvider<HabitsNotifier, HabitsState>((ref) {
  final db = ref.watch(databaseProvider);
  return HabitsNotifier(db);
});
