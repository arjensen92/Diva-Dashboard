import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../gachamon/gachamon_data.dart';
import 'path_service.dart';

/// Loads the Gachadex from `<projectRoot>/gachadex.json`. The JSON file is
/// the only source of truth — there is no hardcoded fallback list. If the
/// file is missing or fails to parse, [gachadex] is left empty and the
/// catching minigame will roll nothing until the user provides a valid
/// `gachadex.json` at the project root.
class GachadexService {
  static String get _jsonPath =>
      p.join(PathService.projectRoot, 'gachadex.json');

  static Future<void> load() async {
    final file = File(_jsonPath);
    if (!await file.exists()) {
      print('[Gachadex] No $_jsonPath found; running with empty gachadex.');
      return;
    }
    try {
      final decoded = jsonDecode(await file.readAsString()) as List;
      final loaded = decoded
          .whereType<Map>()
          .map((m) => Gachamon.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      gachadex = loaded;
      print('[Gachadex] Loaded ${loaded.length} entries from $_jsonPath');
    } catch (e) {
      print(
          '[Gachadex] Failed to parse $_jsonPath: $e — running with empty gachadex.');
    }
  }
}
