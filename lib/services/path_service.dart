import 'dart:io';
import 'package:path/path.dart' as p;

/// Finds the project root by searching a set of candidate paths for a
/// directory that contains an `assets/` subfolder.
///
/// The resolved path is where the app reads data files at runtime
/// (`.env`, `gachadex.json`, `gachamon_game.json`, `video_backgrounds.json`,
/// `dashboard.db`) — see the per-getter helpers at the bottom of this
/// class.
///
/// Resolution order:
///   1. **5 × `..` from the running exe.** A Flutter release exe lives
///      at `<project>/build/windows/x64/runner/Release/<name>.exe`, so
///      five levels up lands back at the project root where `assets/`
///      lives. Always preferred in production.
///   2. **`Directory.current.path`.** Dev mode (`flutter run`) and
///      tests typically start with cwd set to the project root.
///   3. **Last-resort fallback.** Returns the 5-up candidate even if
///      `assets/` wasn't found there — better to log a confusing path
///      than crash on a null root. Most likely cause: the user moved
///      the exe out of the standard `build/windows/...` layout.
class PathService {
  static String? _projectRoot;

  static String get projectRoot {
    if (_projectRoot != null) return _projectRoot!;

    final candidates = [
      // Release exe: 5 × '..' from .../Release/ → project root.
      p.normalize(p.join(p.dirname(Platform.resolvedExecutable),
          '..', '..', '..', '..', '..')),
      // Development: flutter run from the project dir.
      Directory.current.path,
    ];

    for (final candidate in candidates) {
      if (Directory(p.join(candidate, 'assets')).existsSync()) {
        _projectRoot = candidate;
        print('[Path] Project root: $_projectRoot');
        return _projectRoot!;
      }
    }

    // Last resort — accept the 5-up candidate even without assets/.
    _projectRoot = candidates.first;
    print('[Path] Project root (fallback, no assets/ found): $_projectRoot');
    return _projectRoot!;
  }

  static String get assetsDir => p.join(projectRoot, 'assets');
  static String get backgroundsDir => p.join(assetsDir, 'backgrounds');
  static String get sparklesDir => p.join(backgroundsDir, 'sparkles');
  static String get graphicsDir => p.join(backgroundsDir, 'graphics');
  static String get iconsDir => p.join(assetsDir, 'icons');
  static String get holidayIconsDir => p.join(iconsDir, 'holidays');
  static String get envPath => p.join(projectRoot, '.env');
}
