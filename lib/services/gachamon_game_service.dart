import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../gachamon/gachamon_data.dart';
import 'path_service.dart';

/// Persistent state for the gachamon gachapon game — stored at
/// `<projectRoot>/gachamon_game.json`.
class GachamonGameState {
  final int gachaballs;
  final DateTime lastEarnHour; // wall-clock hour we last granted a ball for
  /// Unique-key → times caught. Key format: `"<id>"` for base form,
  /// `"<id>:<form>"` for alt forms (e.g. `"386:Attack"`).
  final Map<String, int> caught;
  /// Unique-key → times caught *as holographic*. Holos don't have their own
  /// gachadex entry — possessing ≥1 holo of a key just renders that key's
  /// card/sticker with the holo shimmer effect applied.
  final Map<String, int> holo;
  /// Unique keys in the order each gachamon was first caught.
  final List<String> catchOrder;

  const GachamonGameState({
    this.gachaballs = 0,
    required this.lastEarnHour,
    this.caught = const {},
    this.holo = const {},
    this.catchOrder = const [],
  });

  GachamonGameState copyWith({
    int? gachaballs,
    DateTime? lastEarnHour,
    Map<String, int>? caught,
    Map<String, int>? holo,
    List<String>? catchOrder,
  }) {
    return GachamonGameState(
      gachaballs: gachaballs ?? this.gachaballs,
      lastEarnHour: lastEarnHour ?? this.lastEarnHour,
      caught: caught ?? this.caught,
      holo: holo ?? this.holo,
      catchOrder: catchOrder ?? this.catchOrder,
    );
  }

  Map<String, dynamic> toJson() => {
        'gachaballs': gachaballs,
        'lastEarnHour': lastEarnHour.toIso8601String(),
        'caught': caught,
        if (holo.isNotEmpty) 'holo': holo,
        'catchOrder': catchOrder,
      };

  static GachamonGameState fromJson(Map<String, dynamic> json) {
    final rawCaught = (json['caught'] as Map?) ?? const {};
    final caught = <String, int>{};
    rawCaught.forEach((k, v) {
      if (v is num) caught[k.toString()] = v.toInt();
    });
    final rawHolo = (json['holo'] as Map?) ?? const {};
    final holo = <String, int>{};
    rawHolo.forEach((k, v) {
      if (v is num) holo[k.toString()] = v.toInt();
    });
    final rawOrder = (json['catchOrder'] as List?) ?? const [];
    // Accept both new string keys and legacy numeric keys (pre-alt-form saves).
    final order = rawOrder.map((e) => e.toString()).toList();
    return GachamonGameState(
      gachaballs: (json['gachaballs'] as num?)?.toInt() ?? 0,
      lastEarnHour: DateTime.tryParse(json['lastEarnHour']?.toString() ?? '')
              ?.toLocal() ??
          _hourFloor(DateTime.now()),
      caught: caught,
      holo: holo,
      catchOrder: order,
    );
  }
}

/// One gachamon-shaped roll the gachapon produced. Used both for the kept
/// catch and for the duplicate-protection re-rolls that never make it
/// into the collection (see [CatchResult.skipped]).
class CatchRoll {
  final Gachamon gachamon;
  final bool isHolo;
  const CatchRoll(this.gachamon, this.isHolo);
}

/// Result of a single gachapon catch. [gachamon]/[isHolo] is the kept
/// catch; [skipped] is every candidate the duplicate-protection loop
/// rejected before landing on the kept one — surfaced so the UI can
/// show the player what they "narrowly missed".
class CatchResult {
  final Gachamon gachamon;
  final bool isHolo;
  final List<CatchRoll> skipped;
  const CatchResult(this.gachamon, this.isHolo, {this.skipped = const []});
}

DateTime _hourFloor(DateTime t) => DateTime(t.year, t.month, t.day, t.hour);

/// Riverpod notifier that owns the gachadex game state: grants gachaballs
/// on a wall-clock schedule (catch-up-aware — if the app was closed across
/// N hour-boundaries it grants N balls on next launch), rolls catches
/// from [rarityWeight] when the user spends a ball, and persists every
/// mutation to `<projectRoot>/gachamon_game.json`. Every successful catch
/// has a 5% chance of coming up holographic (a separate variant tracked
/// in `state.holo`), with duplicate-protection re-rolls on the rarity
/// table — see `spendBallAndCatch` for the details.
class GachamonGameNotifier extends StateNotifier<GachamonGameState> {
  Timer? _ticker;
  final math.Random _rng = math.Random();

  GachamonGameNotifier()
      : super(GachamonGameState(lastEarnHour: _hourFloor(DateTime.now()))) {
    _init();
  }

  Future<void> _init() async {
    await _load();
    _accrueHourlyBalls();
    // Check every minute for the hour rollover.
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      _accrueHourlyBalls();
    });
  }

  /// Path for the game state file. All reads and writes go through here.
  String get _jsonPath =>
      p.join(PathService.projectRoot, 'gachamon_game.json');

  Future<void> _load() async {
    final file = File(_jsonPath);
    if (!await file.exists()) {
      // First run ever: seed lastEarnHour to the current hour floor,
      // start with 1 gachaball so the user can try a catch immediately.
      state = GachamonGameState(
        gachaballs: 1,
        lastEarnHour: _hourFloor(DateTime.now()),
      );
      await _save();
      return;
    }
    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      state = GachamonGameState.fromJson(json);
    } catch (e) {
      print('[GachamonGame] Failed to parse ${file.path}: $e');
    }
  }

  Future<void> _save() async {
    try {
      final file = File(_jsonPath);
      await file.writeAsString(
          const JsonEncoder.withIndent('  ').convert(state.toJson()));
    } catch (e) {
      print('[GachamonGame] Failed to save $_jsonPath: $e');
    }
  }

  /// Grants one gachaball for each wall-clock hour that has elapsed since
  /// [state.lastEarnHour]. Rewards fire at :00, not relative to app launch.
  void _accrueHourlyBalls() {
    final now = _hourFloor(DateTime.now());
    final hoursPassed = now.difference(state.lastEarnHour).inHours;
    if (hoursPassed <= 0) return;
    state = state.copyWith(
      gachaballs: state.gachaballs + hoursPassed,
      lastEarnHour: now,
    );
    _save();
  }

  /// 5% chance a catch comes up holographic.
  static const double _holoChance = 0.05;

  /// Consumes one gachaball, rolls a weighted random gachamon, adds it to
  /// the collection. Returns the [CatchResult] including the holo flag, or
  /// null if no gachaballs are available.
  ///
  /// Duplicate-protection: each candidate (gachamon + holo flag) has a
  /// reroll probability of `0.1 × count-of-this-variant` — a new variant
  /// is always kept, a 5th duplicate rerolls 50% of the time, a 10th
  /// duplicate rerolls 100% (so the collection tops out at 10 per
  /// variant). Holo and non-holo of the same gachamon are counted
  /// independently. All re-rolls happen here, invisibly to the caller.
  CatchResult? spendBallAndCatch() {
    if (state.gachaballs <= 0) return null;

    // Counts a given (key, isHolo) variant currently in the collection.
    int variantCount(String key, bool holo) {
      final total = state.caught[key] ?? 0;
      final holos = state.holo[key] ?? 0;
      return holo ? holos : (total - holos);
    }

    late Gachamon caught;
    late bool isHolo;
    final skipped = <CatchRoll>[];
    const maxAttempts = 30; // safety: if everything is near-capped, bail
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      caught = _rollRandomGachamon();
      isHolo = _rng.nextDouble() < _holoChance;
      final count = variantCount(caught.uniqueKey, isHolo);
      final rerollProb = 0.1 * count;
      if (_rng.nextDouble() >= rerollProb) break; // accept this roll
      // Reroll: stash the rejected candidate so the UI can surface it.
      skipped.add(CatchRoll(caught, isHolo));
    }

    final key = caught.uniqueKey;
    final newCaught = Map<String, int>.from(state.caught);
    newCaught[key] = (newCaught[key] ?? 0) + 1;
    Map<String, int> newHolo = state.holo;
    if (isHolo) {
      newHolo = Map<String, int>.from(state.holo);
      newHolo[key] = (newHolo[key] ?? 0) + 1;
    }
    final newOrder = state.catchOrder.contains(key)
        ? state.catchOrder
        : [...state.catchOrder, key];
    state = state.copyWith(
      gachaballs: state.gachaballs - 1,
      caught: newCaught,
      holo: newHolo,
      catchOrder: newOrder,
    );
    _save();
    return CatchResult(caught, isHolo, skipped: skipped);
  }

  /// Weighted pick — rarity weight × count of gachamon in that tier. A gachamon
  /// with rarity R of total tier size N has effective weight
  /// `rarityWeight[R]` (since all members of a tier share weight uniformly).
  Gachamon _rollRandomGachamon() {
    double total = 0;
    for (final p in gachadex) {
      total += rarityWeight[p.rarity] ?? 0;
    }
    final roll = _rng.nextDouble() * total;
    double cumulative = 0;
    for (final p in gachadex) {
      cumulative += rarityWeight[p.rarity] ?? 0;
      if (roll < cumulative) return p;
    }
    return gachadex.last;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

final gachamonGameProvider =
    StateNotifierProvider<GachamonGameNotifier, GachamonGameState>((ref) {
  return GachamonGameNotifier();
});

/// Generation folder for a given Gachadex ID.
int gachamonGeneration(int id) {
  if (id <= 151) return 1;
  if (id <= 251) return 2;
  if (id <= 386) return 3;
  if (id <= 493) return 4;
  if (id <= 649) return 5;
  if (id <= 721) return 6;
  if (id <= 809) return 7;
  if (id <= 905) return 8;
  if (id <= 1025) return 9;
  return 10;
}

/// Resolved-path cache keyed by Gachamon.uniqueKey. First call per gachamon
/// runs File.existsSync to pick between .png (the common case) and .webp
/// (used by a handful of Arceus/Mimikyu/Pikachu form sprites). Subsequent
/// calls are O(1) — no I/O, no path joining. The dex card opens hundreds
/// of times per session and re-ran the path math every time before this.
final Map<String, String> _spritePathCache = {};

/// Absolute filesystem path for a gachamon sprite, suitable for [File].
/// Base forms resolve to `generation_N/NNNN_<FileStem>.png`. Forms resolve to
/// `<formFolder>/NNNN_<FileStem>-<Form>.png`, except the legacy `alt_forms`
/// folder which omits the underscore between the id and the file stem.
///
/// Falls back to `.webp` if the `.png` doesn't exist on disk — covers the
/// 13 sprites (mostly Arceus type variants) that ship as .webp.
String gachamonSpritePath(Gachamon pk) {
  final cached = _spritePathCache[pk.uniqueKey];
  if (cached != null) return cached;
  final id4 = pk.id.toString().padLeft(4, '0');
  late final String pngPath;
  if (pk.form != null) {
    final folder = pk.formFolder ?? 'alt_forms';
    // alt_forms uses `NNNNStem-Form.png`; every other folder uses `NNNN_Stem-Form.png`.
    final sep = folder == 'alt_forms' ? '' : '_';
    pngPath = p.join(PathService.assetsDir, 'gachamon', folder,
        '$id4$sep${pk.fileStem}-${pk.form}.png');
  } else {
    final gen = gachamonGeneration(pk.id);
    pngPath = p.join(PathService.assetsDir, 'gachamon', 'generation_$gen',
        '${id4}_${pk.fileStem}.png');
  }
  // Try .png first; fall back to .webp if the file isn't there.
  final resolved = File(pngPath).existsSync()
      ? pngPath
      : '${pngPath.substring(0, pngPath.length - 4)}.webp';
  _spritePathCache[pk.uniqueKey] = resolved;
  return resolved;
}
