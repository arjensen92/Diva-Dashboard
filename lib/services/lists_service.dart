import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'path_service.dart';

/// Loads and persists the set of task-list names from `lists.json` at the
/// project root. The file is a plain JSON array of strings:
///
///   ["To-do", "Shopping", "Groceries"]
class ListsService {
  static const _defaults = <String>['To-do', 'Shopping'];

  static String get _path => p.join(PathService.projectRoot, 'lists.json');

  static Future<List<String>> load() async {
    final file = File(_path);
    if (!await file.exists()) {
      await _write(file, _defaults);
      return List.of(_defaults);
    }
    try {
      final decoded = jsonDecode(await file.readAsString()) as List;
      return decoded.whereType<String>().toList();
    } catch (e) {
      print('[Lists] Failed to parse $_path: $e — using defaults');
      return List.of(_defaults);
    }
  }

  static Future<void> save(List<String> names) async {
    await _write(File(_path), names);
  }

  static Future<void> _write(File file, List<String> names) async {
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(names));
  }
}
