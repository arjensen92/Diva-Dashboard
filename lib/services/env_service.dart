import 'dart:io';
import 'path_service.dart';

/// Simple .env file loader that reads directly from disk.
/// Unlike flutter_dotenv, this works with absolute file paths on desktop.
class Env {
  static final Map<String, String> _vars = {};

  static String get(String key) => _vars[key] ?? '';

  static bool get isLoaded => _vars.isNotEmpty;

  static Future<void> load() async {
    // Resolution order:
    //   1. <projectRoot>/.env — primary location, alongside other JSON
    //      data files at the project root.
    //   2. ./.env             — process cwd, useful for dev runs.
    //   3. ../.env            — one level up, covers older installs that
    //      kept the .env outside the Flutter project folder.
    final candidates = [
      '${PathService.projectRoot}\\.env',
      '.env',
      '../.env',
    ];

    for (final path in candidates) {
      final file = File(path);
      if (await file.exists()) {
        final contents = await file.readAsString();
        _parse(contents);
        print('[Env] Loaded ${_vars.length} vars from: $path');
        return;
      }
    }
    print('[Env] WARNING: No .env file found in any candidate path');
  }

  static void _parse(String contents) {
    for (final line in contents.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final eqIndex = trimmed.indexOf('=');
      if (eqIndex < 0) continue;
      final key = trimmed.substring(0, eqIndex).trim();
      final value = trimmed.substring(eqIndex + 1).trim();
      if (key.isNotEmpty && value.isNotEmpty) {
        _vars[key] = value;
      }
    }
  }
}
