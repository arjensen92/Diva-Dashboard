/// Drift schema for the app's local SQLite database. File lives at
/// `<projectRoot>/dashboard.db` (see [_openConnection] at the bottom —
/// falls back to the exe directory if the project-root file doesn't
/// exist). The file is locked while the app is running; Windows can't
/// even rebuild the exe until it's closed.
///
/// Tables:
///  - [Habits]  — one row per habit. `type` is `'boolean'` or `'numeric'`.
///  - [HabitLogs] — per-day log. Uniqueness on `(habitId, date)` enforces
///    one log entry per habit per day; upserting overwrites the value.
///  - [Tasks] — to-do items across multiple `listName`s.
///  - [YoutubeChannels] — subscriptions for the YouTube card.
///  - [AuthTokens] — OAuth access/refresh tokens keyed by `service`
///    ("google", "spotify"). See services/oauth_service.dart.
library;

import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import '../services/path_service.dart';

part 'database.g.dart';

class Habits extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get type => text().withDefault(const Constant('boolean'))(); // 'boolean' | 'numeric'
  RealColumn get target => real().withDefault(const Constant(1.0))();
  TextColumn get unit => text().withDefault(const Constant(''))();
  TextColumn get color => text().withDefault(const Constant('#6366f1'))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class HabitLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get habitId => integer().references(Habits, #id)();
  TextColumn get date => text()(); // YYYY-MM-DD
  RealColumn get value => real().withDefault(const Constant(0.0))();

  @override
  List<Set<Column>> get uniqueKeys => [{habitId, date}];
}

class Tasks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get listName => text().withDefault(const Constant('To-do'))();
  IntColumn get priority => integer().withDefault(const Constant(2))();
  /// Optional due date. Stored as ISO-8601 string — `YYYY-MM-DD` for
  /// date-only or `YYYY-MM-DDTHH:mm` when a specific time is set.
  /// Tasks with this set populate on the calendar views.
  TextColumn get dueDate => text().nullable()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  /// Wall-clock time the task was last toggled to completed. Null when
  /// the task is currently active. Used to order the "Recently
  /// completed" tail in the lists views.
  DateTimeColumn get completedAt => dateTime().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class YoutubeChannels extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get channelId => text().unique()();
  TextColumn get channelName => text()();
  TextColumn get thumbnailUrl => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class AuthTokens extends Table {
  TextColumn get service => text()();
  TextColumn get accessToken => text().nullable()();
  TextColumn get refreshToken => text().nullable()();
  IntColumn get expiresAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {service};
}

@DriftDatabase(tables: [Habits, HabitLogs, Tasks, YoutubeChannels, AuthTokens])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 3;

  @override
  DriftDatabaseOptions get options => const DriftDatabaseOptions(storeDateTimeAsText: true);

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        // Add listName column to tasks
        await customStatement("ALTER TABLE tasks ADD COLUMN list_name TEXT NOT NULL DEFAULT 'To-do'");
      }
      if (from < 3) {
        // Track when each task was completed so the "Recently completed"
        // tail in the lists card can order by most-recent-first.
        await customStatement('ALTER TABLE tasks ADD COLUMN completed_at TEXT NULL');
      }
    },
  );

  // ===== Habits =====
  Future<List<Habit>> getActiveHabits() =>
      (select(habits)..where((h) => h.archived.equals(false))..orderBy([(h) => OrderingTerm.asc(h.sortOrder)])).get();

  Future<Habit> insertHabit(HabitsCompanion entry) async {
    final id = await into(habits).insert(entry);
    return (select(habits)..where((h) => h.id.equals(id))).getSingle();
  }

  Future<void> updateHabit(int id, HabitsCompanion entry) =>
      (update(habits)..where((h) => h.id.equals(id))).write(entry);

  Future<void> deleteHabit(int id) =>
      (delete(habits)..where((h) => h.id.equals(id))).go();

  // ===== Habit Logs =====
  Future<List<HabitLog>> getHabitLogs(String startDate, String endDate) =>
      (select(habitLogs)..where((l) => l.date.isBiggerOrEqualValue(startDate) & l.date.isSmallerOrEqualValue(endDate))).get();

  Future<void> upsertHabitLog(int habitId, String date, double value) async {
    await into(habitLogs).insertOnConflictUpdate(
      HabitLogsCompanion.insert(
        habitId: habitId,
        date: date,
        value: Value(value),
      ),
    );
  }

  // ===== Tasks / Lists =====
  Future<List<Task>> getTasks({String filter = 'all', String? listName}) {
    final q = select(tasks);
    if (listName != null) q.where((t) => t.listName.equals(listName));
    if (filter == 'active') q.where((t) => t.completed.equals(false));
    if (filter == 'completed') q.where((t) => t.completed.equals(true));
    q.orderBy([
      (t) => OrderingTerm.asc(t.completed),
      (t) => OrderingTerm.asc(t.sortOrder),
    ]);
    return q.get();
  }

  Future<Task> insertTask(TasksCompanion entry) async {
    final id = await into(tasks).insert(entry);
    return (select(tasks)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<void> updateTask(int id, TasksCompanion entry) =>
      (update(tasks)..where((t) => t.id.equals(id))).write(entry);

  Future<void> deleteTask(int id) =>
      (delete(tasks)..where((t) => t.id.equals(id))).go();

  /// Reactive stream of every task with a non-null `dueDate`, regardless
  /// of list or completion state. Calendar views watch this so tasks
  /// dropped on a specific day show up alongside Google events.
  Stream<List<Task>> watchTasksWithDueDate() {
    return (select(tasks)..where((t) => t.dueDate.isNotNull())).watch();
  }

  // ===== YouTube Channels =====
  Future<List<YoutubeChannel>> getYoutubeChannels() =>
      (select(youtubeChannels)..orderBy([(c) => OrderingTerm.asc(c.channelName)])).get();

  Future<void> insertChannel(YoutubeChannelsCompanion entry) =>
      into(youtubeChannels).insert(entry, mode: InsertMode.insertOrIgnore);

  Future<void> deleteChannel(int id) =>
      (delete(youtubeChannels)..where((c) => c.id.equals(id))).go();

  // ===== Auth Tokens =====
  Future<AuthToken?> getAuthToken(String service) =>
      (select(authTokens)..where((t) => t.service.equals(service))).getSingleOrNull();

  Future<void> saveAuthToken(AuthTokensCompanion entry) =>
      into(authTokens).insertOnConflictUpdate(entry);

  Future<void> deleteAuthToken(String service) =>
      (delete(authTokens)..where((t) => t.service.equals(service))).go();
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    // Store database in the project root
    final dbPath = p.join(PathService.projectRoot, 'dashboard.db');
    final exePath = p.join(p.dirname(Platform.resolvedExecutable), 'dashboard.db');
    final file = File(File(dbPath).existsSync() ? dbPath : exePath);
    return NativeDatabase.createInBackground(file);
  });
}
