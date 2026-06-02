# Development notes

Quick-reference dev guide for the Kitchen Dashboard codebase. See
[README.md](README.md) for what this stripped distribution ships
with, and [ARCHITECTURE.md](ARCHITECTURE.md) for the full system
overview.

---

## Stack

- **Flutter + Dart** — Windows desktop only (no mobile, no macOS/Linux)
- **Riverpod** — application state (providers, notifiers, listeners)
- **Drift** + `sqlite3_flutter_libs` — local SQLite (`dashboard.db`)
- **googleapis / googleapis_auth** — Google Calendar OAuth
- **webview_windows** — Edge WebView2 host (Spotify embed + YouTube
  background player)
- **audioplayers**, **audio_visualizer** — sound effects + system-audio
  FFT visualizer
- **bonsoir** — mDNS discovery (Chromecast)
- **dio** — general HTTP client

---

## Build

```bash
# CRITICAL: kill the running exe before building — it holds WebView2Loader.dll
tasklist //FI "IMAGENAME eq kitchen_dashboard.exe"
taskkill //PID <pid> //F          # if it's running

cd kitchen_dashboard_public
/c/flutter/bin/flutter build windows --release
# → build/windows/x64/runner/Release/kitchen_dashboard.exe
```

If the build fails with `MSB3027: Could not copy WebView2Loader.dll`,
the exe is still running. Kill it and rebuild.

### Dev mode (hot reload)

```bash
/c/flutter/bin/flutter run -d windows
```

Press `r` for hot reload (preserves state), `R` for hot restart
(resets state), `q` to quit. The app is rendering-heavy — hot reload
is fast for visual tweaks; for memory or perf testing always use the
release build.

---

## Project layout

```
kitchen_dashboard_public/
├── pubspec.yaml              dependencies + bundled assets (only icons/)
├── pubspec.lock
├── analysis_options.yaml
├── README.md                 stripped-distribution overview, what to plug in
├── DEVELOPMENT.md            (this file) dev quick-reference
├── ARCHITECTURE.md           detailed per-subsystem breakdown + design rationale
│
├── gachadex.json             user gachamon catalog (empty in this distro)
├── gachamon_game.json        save state (empty)
├── video_backgrounds.json    YouTube bg URL list (empty)
├── lists.json                task list names (empty)
│
├── assets/
│   ├── fonts/PressStart2P-Regular.ttf
│   └── icons/
│       ├── windows.png       Start button icon (Image.asset)
│       └── dd_icon.apng      active-window taskbar icon (Image.asset)
│
├── lib/                      Flutter/Dart source
│   ├── main.dart             window setup (borderless fullscreen on
│   │                         the secondary monitor)
│   ├── database/database.dart
│   │                         Drift tables (Habits, HabitLogs, Tasks,
│   │                         YoutubeChannels, AuthTokens)
│   ├── gachamon/gachamon_data.dart
│   │                         Gachamon class + lookup helpers
│   ├── screens/              full-screen routes
│   ├── widgets/
│   │   ├── win95.dart        central Win95 design system
│   │   ├── holographic.dart  HoloClock singleton + HoloLayer shimmer
│   │   ├── gachadex_card.dart
│   │                         single-gachamon card display (catch
│   │                         reveal + standalone dex modal)
│   │   ├── gachamon_card.dart
│   │                         dashboard home tile for the gachamon feature
│   │   ├── gachamon_landscape.dart / sticker_sprite.dart / render_layers.dart
│   │   └── *_card.dart       dashboard home-screen cards
│   ├── services/             Drift queries + external APIs (one per feature)
│   ├── providers/            Riverpod state
│   └── theme/                app_colors.dart, app_theme.dart,
│                             animated_backgrounds.dart
│
├── windows/                  CMake / runner / plugin scaffolding
├── web/                      Flutter web placeholder (not built)
│
└── build/windows/x64/runner/Release/   build output
```

---

## Design system

New Win95 chrome **must** compose primitives from
[lib/widgets/win95.dart](lib/widgets/win95.dart) — don't re-define
the palette or re-hand-roll title bars. Exports:

- `Win95` — colors (`gray`, `darkGray`, `veryDark`, `white`,
  `titleBlueLeft/Right`), `titleGradient`, `titleTextShadows`, and
  border factories: `raisedBorder()`, `sunkenBorder()`,
  `pressableBorder({pressed})`
- `Win95TitleBar({title, leading, onMinimize, onMaximize, onClose,
  trailing, buttonSize})`
- `Win95TitleButton({label, size, onTap})` — auto-scales font with size
- `Win95Panel({fillOpacity})` — gray + raised bevel
- `Win95InsetPanel({fillColor, fillOpacity})` — sunken inset
- `Win95Button({pressed, onTap})` — pressable, inverts bevel

---

## PathService (non-obvious)

[lib/services/path_service.dart](lib/services/path_service.dart)
resolves `projectRoot` by walking 5 × `..` from the running exe (a
Flutter release exe at `<project>/build/windows/x64/runner/Release/`
lands back at the project root) and falling back to
`Directory.current.path` for dev runs.

Data files the app reads at runtime — `.env`, `gachadex.json`,
`gachamon_game.json`, `video_backgrounds.json`, `dashboard.db` —
live in the resolved project root. In a release install this is the
folder containing the bundled `assets/`; you can drop the data files
directly next to the `.exe` and they'll be discovered via the 5-up
walk.

---

## Window behavior (main.dart)

- Prefers the non-primary display; falls back to primary if only one
  monitor is present.
- Uses **fake-fullscreen** (a borderless window sized to the monitor)
  — NOT exclusive fullscreen — so `Win+Shift+Left/Right` cross-monitor
  moves still work. A `_MonitorFollowListener` re-engages fullscreen
  on window-move events.
- Set `previewTablet = true` in `main.dart` to develop in a
  1920×1280 windowed mode instead of fullscreen.

---

## OAuth redirect URIs

All three stored-credential flows redirect to localhost:

- Google Calendar: `http://127.0.0.1:8889/callback`
- Spotify:         `http://127.0.0.1:8888/callback`
- YouTube:         uses an API key, not OAuth

Tokens persist in the Drift `AuthTokens` table.

You'll need to create your own OAuth credentials in the Google Cloud
Console (Calendar API) and Spotify Developer Dashboard, then drop the
client ID/secret into a `.env` file at the project root:

```
GOOGLE_CLIENT_ID=...
GOOGLE_CLIENT_SECRET=...
SPOTIFY_CLIENT_ID=...
SPOTIFY_CLIENT_SECRET=...
YOUTUBE_API_KEY=...
```

---

## Windows shell gotchas (Git Bash)

- Forward slashes in paths work in PowerShell and Git Bash; cmd.exe
  prefers backslashes. The doc snippets above assume Git Bash.
- `taskkill //PID 1234 //F` — note the doubled slashes for flags
  when using Git Bash (single-slash gets path-munged by MSYS).
- `dashboard.db` is file-locked while the exe runs; the build system
  can't copy DLLs over the running exe either. Always kill the
  running process first.

---

## Plugging in your own data

This distribution ships with empty JSON data files and zero sprites
or graphics. See [README.md](README.md) → "Plugging in your own
content" for the file formats expected at each location.
