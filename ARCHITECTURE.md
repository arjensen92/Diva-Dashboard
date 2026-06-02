# Kitchen Dashboard — Architecture & File Reference

A Flutter Windows desktop app — a Win95-styled kiosk dashboard that runs
fullscreen on a secondary monitor. Shows a calendar, task lists, habit
tracker, streams Spotify, plays YouTube as an animated background, and
includes a fully playable Gachadex catching minigame with caught-gachamon
overlays scattered across the dashboard.

This document covers how the system is organized, how the major
subsystems hang together, and what each file in `lib/` is responsible
for. It is intended as a sit-down read; jump to the
[per-file reference](#per-file-reference) if you just need to look up
one thing.

---

## Table of contents

1. [Tech stack](#tech-stack)
2. [High-level architecture](#high-level-architecture)
3. [Boot sequence](#boot-sequence)
4. [Design decisions and runtime optimizations](#design-decisions-and-runtime-optimizations)
5. [Major subsystems](#major-subsystems)
   - [Window shell & app entry](#window-shell--app-entry)
   - [Dashboard screen](#dashboard-screen)
   - [Win95 design system](#win95-design-system)
   - [Theme & background system](#theme--background-system)
   - [Effects quality system](#effects-quality-system)
   - [Sparkle layer](#sparkle-layer)
   - [Sticker layer](#sticker-layer)
   - [Holographic clock and shimmer](#holographic-clock-and-shimmer)
   - [Gachamon game](#gachamon-game)
   - [Spotify integration](#spotify-integration)
   - [YouTube background player](#youtube-background-player)
   - [Calendar](#calendar)
   - [Tasks & lists](#tasks--lists)
   - [Habits](#habits)
   - [OAuth & persistence](#oauth--persistence)
   - [Audio visualizer & casting](#audio-visualizer--casting)
6. [Per-file reference](#per-file-reference)

---

## Tech stack

- **Flutter / Dart** for the UI layer (Windows desktop only)
- **Riverpod** for app-wide state (providers, notifiers, listeners)
- **Drift** + `sqlite3_flutter_libs` for the local SQLite database
  (`dashboard.db`)
- **googleapis** + **googleapis_auth** for Google Calendar OAuth
- **webview_windows** (Edge WebView2) for the Spotify player browser
  embed and the YouTube background player
- **audioplayers**, **audio_visualizer** for sound effects and the
  system-audio FFT visualizer
- **bonsoir** for mDNS discovery (Chromecast)
- **dio** for general HTTP

The `.env` file at the project root holds OAuth credentials and the
YouTube Data API key. See `lib/services/env_service.dart`.

---

## High-level architecture

The app is one fullscreen `MaterialApp` with a single home screen
(`DashboardScreen`) plus four "full-screen" routes (Calendar, Lists,
Gachamon, Spotify) that animate in over the dashboard via a custom
zoom-in route. The visualizer screen and Habits full-screen exist as
additional routes.

### Render hierarchy at runtime

```
MaterialApp
└── builder Stack                    (in main.dart)
    ├── YouTubeBackgroundPlayer      (only when active and enabled)
    └── Navigator
        └── DashboardScreen          (or pushed full-screen route)
            └── Scaffold body Stack
                ├── AnimatedBackground
                │   └── (color | image | placeholder for YT)
                ├── SparkleLayer     (single CustomPainter for ~50–350 sparkles)
                ├── PageView OR Grid (the four card tiles)
                ├── DashboardStickerLayer (single CustomPainter for ~0–160 stickers
                │                          + invisible hit zones for drag/rotate/resize)
                ├── Sticker drawer panel (right edge)
                ├── Background picker drawer (left edge)
                ├── Settings drawer (left edge)
                └── Win95Taskbar + StartMenu
```

Each child of the body stack is conditionally inserted based on Riverpod
state — for example, switching the background to a static color removes
`YouTubeBackgroundPlayer` from the tree (and disposes the WebView).

### State graph

State lives in Riverpod providers. The major ones:

| Provider | Type | Purpose |
|---|---|---|
| `themeProvider` | `StateNotifier<DashboardTheme>` | Current accent color + optional background image or YT video. Randomizes hourly. |
| `sparkleQualityProvider` | `StateProvider<EffectQuality>` | off/low/med/max sparkle count |
| `stickerQualityProvider` | `StateProvider<EffectQuality>` | off/low/med/max stickers per card |
| `videoBackgroundEnabledProvider` | `StateProvider<bool>` | Enables YT background and random-pool inclusion |
| `sparkleImagesProvider` | `StateProvider<List<PlacedOverlay>>` | The current scattered sparkle positions |
| `graphicsImagesProvider` | `StateProvider<List<PlacedOverlay>>` | The current scattered sticker positions |
| `gridModeProvider` | `StateProvider<bool>` | Carousel ↔ grid toggle |
| `startMenuOpenProvider` | `StateProvider<bool>` | Start menu visibility |
| `bgPickerOpenProvider` / `stickerPanelOpenProvider` / `settingsPanelOpenProvider` | `StateProvider<bool>` | Drawer visibility |
| `gachamonGameProvider` | `StateNotifier<GachamonGameState>` | Gachaballs, caught Gachamon, holo variants |
| `calendarProvider` | `StateNotifier<CalendarState>` | Google Calendar connection + event window |
| `dueTasksProvider` | `StreamProvider<List<Task>>` | Live stream of every task with a due date — used to merge tasks into the calendar |
| `spotifyProvider` | `StateNotifier<SpotifyState>` | Spotify connection + 5-second player polling |
| `habitsProvider` | `StateNotifier<HabitsState>` | Active habits + log values |
| `tasksProvider` (`listsProvider`) | `StateNotifier<ListsState>` | Active list + tasks split into active/recently-completed |
| `currentDateProvider` | `StateNotifier<DateTime>` | Ticks at midnight so the calendar repaints daily |

State is in-memory only for the visual quality settings; everything
else persists either through Drift (calendar tokens, habits, tasks),
through plain JSON files at the project root (gachamon game state,
gachadex, video backgrounds, list names), or through OAuth tokens
in the database.

---

## Boot sequence

`main()` (lib/main.dart) does the following before showing the window:

1. `WidgetsFlutterBinding.ensureInitialized()`
2. `Env.load()` — read `.env` from the project root
3. `VideoBackgroundService.load()` — read and enrich
   `video_backgrounds.json` (calls YouTube API to fill in title +
   duration + aspect ratio if missing)
4. `GachadexService.load()` — read `gachadex.json` (or seed from the
   built-in `seedGachadex` on first run)
5. `windowManager.ensureInitialized()` and configuration —
   borderless fullscreen on the secondary monitor (or primary if
   only one display)
6. `runApp(ProviderScope(child: KitchenDashboardApp()))`

After that, `KitchenDashboardApp.build` mounts `DashboardScreen` as the
home and wraps it in the `MaterialApp.builder` `Stack` that hosts the
optional `YouTubeBackgroundPlayer`.

`DashboardScreen.initState` then enumerates files for sparkles and
graphics (`OverlayService.listImageFiles`) and kicks off the first
randomization. The hourly theme timer is owned by `ThemeNotifier`.

---

## Design decisions and runtime optimizations

The app went through several rounds of perf surgery. This section
catalogs the non-obvious architectural choices, the problems they
solve, and the tradeoffs each one carries. They're grouped by category
so you can find related decisions together.

### Rendering pipeline

#### Single-painter consolidation for sparkles and stickers

**Problem:** the original implementation rendered each of the 300–500
sparkles and each of the ~50 placed stickers as its own widget — one
`RepaintBoundary` + one `Image.file` decoder + one compositor layer
per item. With 350+ widgets in two stacks, the widget tree was huge,
the raster cache thrashed on every frame, and Flutter's per-widget
`shouldRepaint` checks dominated CPU time.

**Solution:** `SparkleLayer` and `DashboardStickerLayer` each render
every item in a *single* `CustomPainter.paint()` call. One compositor
layer total. The layers share the decoded image cache
(`AnimatedFrame`) across every reference to the same path — 300
sparkles using the same `.gif` decode it once.

**Tradeoff:** can't use Flutter widgets for individual stickers
(animations, taps), so gestures are handled via separate hit-zone
widgets layered on top (see [Hit zone architecture](#hit-zone-architecture-for-stickers)
below). Files: `lib/widgets/sparkle_layer.dart`, `lib/widgets/sticker_layer.dart`.

#### Pre-baked outlined sprite cache

**Problem:** `paintStickerToCanvas` builds the white sprite outline by
stamping the source image 16 times around two concentric rings (12
outer + 4 inner) tinted via a `srcATop` color filter. That's 17 draw
calls per sticker per frame, which dominates the dex grid's paint
cost. With ~12 visible cells × 17 draws = 200+ draw calls/frame just
for outlines.

**Solution:** `StickerBakeCache` (in
`lib/widgets/sticker_bake_cache.dart`) renders the entire outline +
sprite combination *once* into a `ui.Image` via an off-screen
`PictureRecorder`, keyed by `(spritePath, sizeBucket,
outlineRadiusBucket)` with three size buckets (64 / 128 / 256). Per
frame, the painter does one `drawImageRect` of the cached image
instead of 17 stamps. Holo shimmer is *not* baked because it
animates — it's still drawn live on top.

**Tradeoff:** ~30–40 MB resident in the cache during a long session.
First paint of a sprite still uses the live multi-stamp path while
the bake completes asynchronously; once the bake finishes, a
`_bakeVersion` counter triggers a repaint that switches to the fast
path. Bakes are idempotent — concurrent paints for the same key
short-circuit. Files: `sticker_bake_cache.dart`,
`sticker_sprite.dart`, `sticker_layer.dart`.

#### AnimatedFrame shared decode cache

**Problem:** Flutter's `Image.file` widget caches decoded bitmaps via
`PaintingBinding.imageCache` keyed by `(file, scale)` — but the cache
holds full-resolution decodes, evicts under memory pressure, and
doesn't expose the underlying `ui.Image` for direct use in custom
painters.

**Solution:** `AnimatedFrame` (in `lib/widgets/animated_frame.dart`)
is a path-keyed wrapper holding a single `ui.Image` (the current
frame) plus optional `ui.Codec` for animated GIFs/APNGs. Sparkle and
sticker layers maintain a `Map<String, AnimatedFrame> _cache` so 300
sparkles using the same path share one decode. Frame ticking is
driven by a single shared `Ticker` per layer with delta-time
accumulation; only paths whose images are loaded participate.

**Tradeoff:** we own cache lifecycle ourselves
(`_evictStale(activePaths)` runs on each rebuild), and have to
explicitly dispose `current` and `_liveCodec` to free GPU memory.

#### Aspect-preserving decode

**Problem:** the initial sticker-layer optimization passed both
`targetWidth: 256, targetHeight: 256` to
`ui.instantiateImageCodec` to limit memory. But with both dimensions
specified, Flutter forces the exact resolution and squashes
off-aspect images — wide banner stickers became squares, tall
portrait stickers became squares.

**Solution:** `AnimatedFrame.load` peeks at source dimensions via
`ui.ImageDescriptor.encoded` *before* decoding, then computes a
contain-fit scale (capped at 1.0× so we never upscale). A wide
sticker now decodes as e.g. 256×128 instead of forced 256×256. The
`_StickerLayerPainter` non-Gachamon branch also paints into a
contain-fitted destination rect inside the renderSize square so
gestures still target the full square but the visible image keeps
its aspect.

**Tradeoff:** one extra `ImageDescriptor` round trip per load — small
parsing cost, dwarfed by the actual decode. File:
`lib/widgets/animated_frame.dart`.

#### HoloClock singleton

**Problem:** the holographic shimmer effect needs continuous
animation. Naïvely, every Gachamon sticker that wants holo would
register its own `Ticker` or `AnimationController` — 50 Gachamon
stickers = 50 frame callbacks per frame.

**Solution:** `HoloClock` (in `lib/widgets/holographic.dart`) is a
singleton `ChangeNotifier` that ticks on a single
`SchedulerBinding.addPostFrameCallback` chain, exposing monotonic
`seconds`. Every holo widget registers as a listener; the callback
only runs while at least one listener exists. The Gachadex card,
sticker layer's Gachamon path, and Gachamon landscape all consume the
same instance.

**Tradeoff:** none significant — pure win. Files:
`holographic.dart`, all sticker/sprite consumers.

#### Codec disposal for static images

**Problem:** `ui.Codec` retains the compressed image bytes alongside
the decoded frames so it can re-decode on `getNextFrame()`. For
animated GIFs that's necessary; for static PNGs the codec is dead
weight after the first frame is extracted.

**Solution:** `AnimatedFrame.load` checks `codec.frameCount` after
the first frame. If it's 1 (static image), `codec.dispose()` runs
immediately and the codec reference is set to null. Only animated
images keep the codec alive.

**Tradeoff:** none — the codec was never being used after the first
decode for static images. File: `lib/widgets/animated_frame.dart`.

### Scrolling and layout

#### Lazy GridView for the Gachadex

**Problem:** the Gachadex grid was wrapped in a
`SingleChildScrollView`, with `_GachadexGrid` running its own
`GridView.builder` configured with `shrinkWrap: true` and
`NeverScrollableScrollPhysics`. That combination forces the
GridView to lay out *every cell on every frame* to compute its
natural height — defeating the entire point of `GridView.builder`'s
lazy rendering. With 1000+ cells × 17-stamp `StickerSprite` paint
each, entering the dex screen locked the UI thread for hundreds of
ms.

**Solution:** removed the parent `SingleChildScrollView` (the
landscape banner that originally justified it had been removed
earlier) and let `GridView.builder` own its own scrolling with the
`scrollController`. Now only ~12 currently-visible cells call
`itemBuilder`. Combined with the sticker bake cache, dex entry is
now near-instantaneous.

**Tradeoff:** none. The intermediate "batch by 100" workaround that
came before this fix was treating a symptom; the underlying bug was
the nested-scroll setup defeating laziness. File:
`lib/screens/gachamon_full_screen.dart`.

#### Off-screen sticker culling

**Problem:** the dashboard sticker layer holds positions for all
~50 stickers across all card pages, but only a fraction are visible
at any given scroll position. Painting and frame-ticking off-screen
stickers wastes both GPU and CPU.

**Solution:** the painter computes each sticker's screen-space
position from the live page-view scroll offset and skips
`drawImageRect` when its bounds fall outside the viewport (with a
small lookahead margin). The frame-tick pass also skips off-screen
paths so animated GIFs pause when scrolled away.

**Tradeoff:** the cull check runs per-sticker per-frame, but it's
cheap arithmetic — way cheaper than a `drawImageRect` for a sticker
nobody can see. File: `lib/widgets/sticker_layer.dart`.

### Image cache strategy

#### Image cache warmup on full-screen entry

**Problem:** `Image.file` decodes synchronously on first use and
caches the result in `PaintingBinding.imageCache`. The catch dialog
opens an `Image.file(File(pokeballPath))` for the title bar, the
counter, and the main catch button — the first dialog open after
booting incurred a visible decode flash for each.

**Solution:** `_GachamonFullScreenState.initState` schedules a
post-frame callback that *awaits* a precache of the two pokeball
icons (`Poké_Ball_icon.svg.png` and `pokeball.png`). They're tiny
files; awaiting them adds a few ms but guarantees they're in the
cache before the catch dialog can render. A static
`_imageCacheWarmed` flag ensures we only warm once per session.

**What we tried and removed:** the warmup originally also
batch-precached every Gachamon sprite (1389 of them) under the
theory that the dex card opens would benefit. That broke
spectacularly — `precacheImage` puts decoded bitmaps in
`imageCache`, but the dex *grid* cells use `StickerSprite`, which
loads via `ui.instantiateImageCodec(bytes)` directly, bypassing
`imageCache` entirely. The 1389 concurrent precaches were pure disk
thrash with zero payoff for the grid (and limited payoff for the
dex card). Working set ballooned to 23 GB and the dex screen took
60+ seconds to populate. Pulled in commit `fd6ca69`.

The grid warms naturally now: `GridView.builder` is lazy (~12
visible cells), each `StickerSprite` loads + bakes its sprite via
the bake cache pipeline, and subsequent renders hit the bake cache's
fast path. No background starvation. File:
`lib/screens/gachamon_full_screen.dart`.

#### Sprite path cache + .webp fallback

**Problem:** `gachamonSpritePath` is called every time a dex card or
grid cell renders — hundreds of times per session — and was
re-running the path-joining math each time. Worse, the function
hardcoded `.png` extension, but 13 sprites (Arceus type variants,
Pikachu Flying, Mimikyu Busted) ship as `.webp` and were rendering
the red-pokeball errorBuilder because the file genuinely didn't
exist at the resolved path.

**Solution:** a static `Map<String, String> _spritePathCache` keyed
by `Gachamon.uniqueKey`. First lookup per gachamon does one
`File.existsSync` to pick between `.png` (the common case) and
`.webp` (fallback); subsequent lookups are O(1) hashmap hits.

**Tradeoff:** 1389 entries in a static map — trivial memory cost.
File: `lib/services/gachamon_game_service.dart`.

#### Gachamon smattering cap

**Problem:** the dashboard's Gachamon notebook tile rendered one
sprite per *catch* — so a player with 200 catches got 200 active
`StickerSprite` widgets, each with its own decode + holo listener,
crammed into a 200 px tile. Overcrowded visually and a real per-frame
paint cost.

**Solution:** `_Smattering` caps at 20 sprites with a
content-addressed sample seed (hashes the `(uniqueKey, copyIndex)`
pairs of all instances). The seed is stable across rebuilds, so the
visible set doesn't reshuffle every frame; it only changes when
you catch something new. Sprite size bumped from 40–64 px to 70–110
px so the smaller set still fills the page.

**Tradeoff:** if you catch 200 Gachamon, you only see 20 of them on
the tile. The full collection is still visible in the dex grid.
File: `lib/widgets/gachamon_card.dart`.

### Gesture routing and hit testing

#### Hit zone architecture for stickers

**Problem:** the single-painter consolidation rendered all stickers
in one `CustomPaint`, which made gesture handling hard — you can't
attach `GestureDetector` to individual paint operations. But
stickers must still be draggable / rotatable / resizable.

**Solution:** the dashboard sticker layer is a `Stack` with two
children: the `CustomPaint` (visual) wrapped in `IgnorePointer`,
and a list of `Positioned(DraggableSticker)` hit zones — one
invisible `SizedBox.expand` per visible sticker. Gestures route
exclusively through the hit zones; the painter never absorbs them.
Each hit zone uses `key: ValueKey(s.path)` so Flutter keeps the
correct `DraggableSticker` element alive across 60 fps rebuilds
driven by `HoloClock` — without the key, stale pointer state from
one element could be applied to a different sticker's hit zone.

**Tradeoff:** the hit zone covers the renderSize square even for
stickers with non-square aspect ratios, so taps on the transparent
padding still register — usually desired. File:
`lib/widgets/sticker_layer.dart`.

### User-facing controls

#### Per-effect quality tiers

**Problem:** the app originally had a binary `effectsEnabledProvider`
master switch. Users couldn't keep stickers but drop sparkles, or
turn off the YouTube background but keep the rest. Practical
result: the toggle was always left on.

**Solution:** `effects_quality.dart` exposes three independent
providers:

- `sparkleQualityProvider` — `EffectQuality` (off/low/med/max)
  mapping to 0 / 50 / 150 / 250 sparkles
- `stickerQualityProvider` — same enum mapping to 0 / 8 / 20 / 40
  stickers per card-page
- `videoBackgroundEnabledProvider` — plain `bool` (the WebView is
  binary; tiered didn't make sense)

The Settings drawer renders these as 4-button quality rows + one
2-button on/off toggle. Quality changes apply immediately via
`ref.listen` hooks in `_DashboardScreenState`.

**Tradeoff:** in-memory only — settings reset on app launch. We
chose this deliberately so a fresh boot is always in a known state;
adding Drift-backed persistence would mirror the `AuthTokens`
pattern. File: `lib/providers/effects_quality.dart`,
`lib/widgets/settings_panel.dart`.

### Subsystem lifecycle

#### Lazy YouTube background

**Problem:** an embedded WebView2 instance is the heaviest single
runtime subsystem in the app — its own process, its own JS engine,
its own GPU surface. Originally the player was instantiated on
startup and lived for the whole session.

**Solution:** the `YouTubeBackgroundPlayer` widget is only mounted
in the tree when both `videoBackgroundEnabledProvider == true` *and*
`theme.youtubeBackground != null`. Switching to a static color or
image background causes the conditional to fail, removes the widget
from the tree, calls `dispose()` which tears down the
`WebviewController` and closes the local HTTP server. The
WebView2 process exits.

**Tradeoff:** enabling a video background incurs a ~1–2 second
warmup as Chromium initializes the WebView and the HTTP server
binds + serves the embed page. Worth it for the memory drop — the
WebView2 process holds ~300–500 MB while running. File:
`lib/widgets/youtube_background.dart`, `lib/main.dart`.

#### YouTube card removal

**Decision:** a 423-line YouTube dashboard card and its supporting
service / provider / Drift `YoutubeChannels` table existed to show
the user a clickable list of subscribed channels with thumbnails.
The card itself instantiated a *second* persistent WebView2 process
(the channel list fetched recent videos via the YouTube Data API,
but the card showed a small embedded YouTube player as a preview).

**Resolution:** removed the entire feature in commit `ebe6c88`. The
dashboard now has Calendar / Lists / Gachamon / Spotify (4 cards
instead of 5). Drift `YoutubeChannels` table left in place since
removing it requires a schema migration with no runtime memory
benefit.

**Tradeoff:** the YouTube *background* feature stayed (still useful
as ambient video) — it lazily initializes per the previous section.
This was the single biggest one-shot memory win: a full Chromium
process disappeared from the process tree.

### Asset and disk strategy

#### Pubspec asset bundling cleanup

**Problem:** `pubspec.yaml` originally bundled `assets/backgrounds/`
(221 MB of background images, sticker graphics, sparkles). But
nothing in the codebase reads them via `Image.asset` or
`rootBundle.load` — sparkles, stickers, and backgrounds all load
from disk via `File()` paths through `OverlayService.listImageFiles`
and `getBackgroundImages()`. The bundled copies were dead weight
mmap'd into the process address space.

**Solution:** removed the three asset directives from `pubspec.yaml`.
Disk copies stay where they are; the app keeps reading them via
`File()` unchanged. `assets/icons/` and `assets/sounds/` remain
bundled because two `Image.asset` calls in `win95_taskbar.dart`
genuinely need them.

**Tradeoff:** none — the assets weren't being read via the bundle.
File: `pubspec.yaml`, commit `b30beb7`.

### Memory hygiene

#### Stale cache eviction

**Problem:** `SparkleLayer` and `DashboardStickerLayer` each
maintain a `Map<String, AnimatedFrame>` keyed by sprite path. When
the user shuffles the theme, the active path set changes — but the
caches retained entries for paths no longer in use, leaking decoded
bitmaps.

**Solution:** both layers run an `_evictStale(activePaths)` pass on
each rebuild. Paths in the cache but not in the current
`PlacedOverlay` list are disposed and removed. Compute is
proportional to cache size, runs once per shuffle.

**Tradeoff:** none. Files: `sparkle_layer.dart`, `sticker_layer.dart`.

#### `IgnorePointer` + `RepaintBoundary` discipline

The `CustomPaint` rendering the sticker visual layer is wrapped in
`IgnorePointer` so it's invisible to hit testing — gestures route
exclusively through the `DraggableSticker` hit zones. The same
painter is also wrapped in `RepaintBoundary` so frame-by-frame
sticker animation doesn't invalidate the parent dashboard's raster.
Both are tiny widget tree additions but each prevents a class of
bug or performance pitfall.

---

## Major subsystems

### Window shell & app entry

**`lib/main.dart`** is responsible for the desktop-window setup. It
prefers the non-primary monitor, uses fake-fullscreen (a borderless
window sized to the monitor) so `Win+Shift+Left/Right` cross-monitor
moves still work, and uses a `_MonitorFollowListener` to re-engage
fullscreen when the OS moves the window. The `previewTablet` constant
flips into a 1920×1280 dev mode.

`KitchenDashboardApp.builder` is where the YouTube background lives —
`Stack` with the player at the bottom (only when
`videoBackgroundEnabledProvider` is true and `theme.youtubeBackground`
is non-null) and the `Navigator`'s child on top. This means full-screen
routes pushed on top of the dashboard keep the video playing
underneath uninterrupted.

### Dashboard screen

**`lib/screens/dashboard_screen.dart`** is the central hub and the
single largest file. It owns:

- The four card definitions (`_CardDef` for Calendar, Lists, Gachamon,
  Spotify) and their carousel/grid presentation
- The `PageController`-driven horizontal carousel with fractional
  scroll-offset tracking (used by the sticker layer to slide stickers
  off-page in sync)
- Two drawer panels (background picker on the left, sticker drawer on
  the right) with their open/close providers
- The `ThemeNotifier` that randomizes hourly and on user action
- The sparkle and sticker generators and the providers they push into
- The gachamon-sticker tab integration that swaps `_graphicFiles` for
  caught-Gachamon sprite paths
- The start menu wiring: shuffle, change background, toggle grid,
  open settings, exit

Notable methods:

- `shuffleEverything()` — randomize theme + regenerate sparkles + stickers
- `_randomizeSparklesOnly` / `_randomizeGraphicsOnly` — read the
  quality providers and generate accordingly; both noop if quality is
  off
- `_onSparkleQualityChanged` / `_onStickerQualityChanged` — `ref.listen`
  hooks so changing the slider in Settings instantly re-renders without
  a theme shuffle
- `_gachamonStickers(ref)` / `_holoSpritePaths(ref)` — derive the active
  sticker file list when the Gachamon tab is selected
- `_openFullScreen(context, screen)` — pushes a `ZoomInRoute`, plays
  the PC jingle if the destination is the Gachamon screen

### Win95 design system

**`lib/widgets/win95.dart`** is the single source of truth for the
Win95 chrome. Anything that wants to look like Win95 — title bars,
panels, buttons — *must* compose primitives from this file rather than
re-defining colors or hand-rolling bevel borders.

Exports:

- `Win95` static class with the canonical palette (`gray`, `darkGray`,
  `veryDark`, `white`, `titleBlueLeft`, `titleBlueRight`), gradients,
  and border factories: `raisedBorder`, `sunkenBorder`,
  `pressableBorder({pressed})`
- `Win95TitleBar` — blue gradient bar with title text, optional
  leading icon, optional trailing widgets, and optional min/max/close
  buttons
- `Win95TitleButton` — square beveled title button with auto-scaled
  font
- `Win95Panel` — gray fill + raised bevel, used for windows and menus
- `Win95InsetPanel` — sunken inset background used for content areas
- `Win95Button` — pressable beveled button that flips bevel on press

The taskbar and start menu live in **`lib/widgets/win95_taskbar.dart`**.

### Theme & background system

**`lib/theme/animated_backgrounds.dart`** holds the `DashboardTheme`
(accent color + optional background image + optional YT video) and
the `themePalette` of pastel accents. Public functions:

- `randomAccent()` — pick a color from the palette
- `getBackgroundImages()` — enumerate background image files from
  `assets/backgrounds/` (disk, *not* the asset bundle)
- `AnimatedBackground` widget — renders the active theme: color
  fill, image via `Image.file`, or placeholder (when YT is active —
  the YT player is rendered at the app level by `main.dart`)

`ThemeNotifier` (in `dashboard_screen.dart`) consumes
`videoBackgroundEnabledProvider` to decide whether YT entries are
included in `randomize()`'s pool.

### Effects quality system

**`lib/providers/effects_quality.dart`** is the foundation for the
new Settings panel.

- `EffectQuality` enum: `off`, `low`, `med`, `max`
- Extension getters:
  - `sparkleCount` — off=0, low=50, med=150, max=350
  - `stickersPerCard` — off=0, low=8, med=20, max=40
  - `label` — short user-facing string
- Providers:
  - `sparkleQualityProvider`
  - `stickerQualityProvider`
  - `videoBackgroundEnabledProvider` (plain `bool`, not `EffectQuality`,
    because the WebView is binary)
  - `settingsPanelOpenProvider`

The Settings drawer (`lib/widgets/settings_panel.dart`) renders a
4-button row per quality provider and a 2-button On/Off row for the
video bg.

### Sparkle layer

**`lib/widgets/sparkle_layer.dart`** is a single-painter rewrite of
the original per-sparkle widget tree. Architecture:

- `_SparkleLayerState._cache: Map<String, AnimatedFrame>` — each
  unique image path is decoded once and shared across every sparkle
  that references it (300+ identical sparkles → 1 decode)
- A single `Ticker` advances animation frames using delta time
- Stale cache entries are evicted in `build()` whenever the active
  path set changes
- A single `CustomPainter` (`_SparkleLayerPainter`) draws every
  sparkle in one pass

`AnimatedFrame.load(path, targetWidth: 128, targetHeight: 128)` decodes
sparkle images at display size while preserving aspect ratio (via
`ImageDescriptor.encoded` + proportional scaling — see the [aspect
ratio fix](#sticker-layer) below).

The deprecated **`lib/widgets/sparkle_overlay.dart`** still exists for
the full-screen views — it renders sparkles as individual widgets
(slower, but only over a single full-screen view, not the dashboard).

### Sticker layer

**`lib/widgets/sticker_layer.dart`** does for stickers what the
sparkle layer does for sparkles, plus:

- Routes drag/rotate/resize gestures through invisible
  `DraggableSticker` hit zones layered on top of the painter
- Wraps the painter in `IgnorePointer` so visual paint never absorbs
  hits (gesture routing goes exclusively through the hit zones)
- Adds `ValueKey(s.path)` to each `Positioned` hit zone so Flutter
  keeps the correct `DraggableSticker` element alive across 60 fps
  rebuilds driven by `HoloClock`
- Uses one shared `HoloClock` listener for holo shimmer + bobbing +
  GIF frame cycling for the entire layer

The painter has two paths:

- **Gachamon stickers** — go through `paintStickerToCanvas` (in
  `lib/widgets/sticker_sprite.dart`) which paints a white outline,
  the sprite, and an optional holo shimmer with proper compositing
  isolation via `saveLayer`
- **Plain graphic stickers** — drawn directly with `drawImageRect`
  using a contain-fitted destination rect so off-aspect graphics
  keep their natural proportions

**`lib/widgets/animated_frame.dart`** is the shared image container
both layers use. `AnimatedFrame.load()`:

- Reads bytes from disk
- Peeks at source dimensions via `ImageDescriptor.encoded` if both
  target dimensions are given, computes a proportional bounding-box
  scale (capped at 1.0× — never upscales)
- Decodes via `ui.instantiateImageCodec` at the proportional target
- Disposes the codec immediately if `frameCount == 1` (statics don't
  need it; only animated GIFs/APNGs keep the codec alive for
  `getNextFrame` cycling)
- `tick(delta)` returns true when the next frame is due
- `advance(onDone)` decodes the next frame and replaces `current`

### Holographic clock and shimmer

**`lib/widgets/holographic.dart`** has two pieces:

- `HoloClock` — a singleton `ChangeNotifier` that ticks on a single
  `SchedulerBinding.instance.addPostFrameCallback` chain, exposing
  monotonic seconds. One frame callback for every holo-using widget
  in the app, *not* one per sticker — and the callback only runs while
  someone is listening
- `HoloLayer` — wraps a child with shimmer overlay via `CustomPaint`
  and a `srcATop` blend so the shimmer respects the sprite's alpha

The Gachadex card, the sticker layer's Gachamon path, and the Gachamon
landscape all consume `HoloClock` for synchronized animations.

### Gachamon game

The catching minigame is the most complex feature. It spans six files:

- **`lib/gachamon/gachamon_data.dart`** — `Gachamon` class, `GachamonRarity`
  enum, `rarityWeight` table, the global mutable `gachadex` list, and
  `seedGachadex` (Gen 1 baseline used on first run). `Gachamon.uniqueKey`
  returns `'<id>'` for base forms or `'<id>:<form>'` for alt forms
  (Galarian, Mega, etc.)
- **`lib/services/gachadex_service.dart`** — loads
  `gachadex.json` from the project root and replaces `gachadex`
- **`lib/services/gachamon_game_service.dart`** —
  `GachamonGameState` (gachaballs, caught map, holo map, catch order),
  `GachamonGameNotifier` with hourly ball accrual, gachapon roll with
  duplicate protection and 5% holo chance, persistence to
  `gachamon_game.json`
- **`lib/screens/gachamon_full_screen.dart`** — the gachapon screen
  with the catch dialog, Gachadex grid, and gachaball counter
- **`lib/widgets/gachadex_card.dart`** (~1000 lines) — the single-Gachamon
  card display with rarity-tier borders (mythical uses an animated
  rainbow gradient), evolution chain, dex entry, type icons, and
  catch-reveal modal
- **`lib/widgets/gachadex_card_effects.dart`** — `FillSparkles` and
  `RingSparkles` painter widgets that blink star sparkles in
  rectangles or rings
- **`lib/widgets/gachamon_landscape.dart`** — procedural background
  (sky/grass gradient + clouds) with caught Gachamon positioned at
  stable seeded coordinates
- **`lib/widgets/gachamon_card.dart`** — the dashboard tile rendered
  as a spiral-bound notebook with a smattering of caught gachamon on
  top. Caps at 20 sprites with a content-addressed sample seed (stable
  until the catch list changes; reshuffles when you catch something
  new) and renders sprites at 70–110 px so the smaller set fills the
  page

Game economy: one gachaball per wall-clock hour (catch-up aware on
relaunch). A roll picks rarity from the weight table, then picks a
gachamon from that tier; if you already own it, it re-rolls until a new
one is found. Independent 5% chance for holo variant.

### Spotify integration

- **`lib/services/spotify_service.dart`** — Spotify Web API client
  extending `OAuthApiClient`. Endpoints: player, devices, search,
  playlists, playback control. Errors are swallowed silently so a
  paused or hung Spotify doesn't break the UI
- **`lib/services/spotify_webview.dart`** — helpers for the embedded
  Spotify web player WebView (audio blocker script, scroll forwarding)
- **`lib/providers/spotify_provider.dart`** — `SpotifyNotifier` polls
  `/me/player` every 5 seconds when connected, wraps playback methods
  with delay-and-reflect so the UI updates after the API has time to
  settle
- **`lib/widgets/spotify_card.dart`** — dashboard tile with a spinning
  CD album art (rotating annular `ClipPath` of the album art with an
  iridescent sweep gradient overlay) and play/pause/next/prev controls.
  Native Flutter widgets only — no WebView on the card
- **`lib/screens/spotify_full_screen.dart`** — full-screen view with
  search, playlist list, queue, and playlist-detail embedded WebView
  (only created when you click into a playlist; disposed on close)

### YouTube background player

**`lib/widgets/youtube_background.dart`** runs a tiny local HTTP server
that serves a custom HTML page containing the YouTube IFrame Player API
embed. Why: YouTube blocks `file://` embeds. The page does the
"BoxFit.cover" math itself in JavaScript so the video fills the screen
without letterboxing.

The widget is only inserted into the tree by `main.dart` when both
`videoBackgroundEnabledProvider` is true and `theme.youtubeBackground`
is non-null. Switching to a static background tears down the WebView
and HTTP server via `dispose()`.

### Calendar

- **`lib/services/calendar_service.dart`** — Google Calendar REST
  client extending `OAuthApiClient` (`getEvents`, `createEvent`,
  `deleteEvent`)
- **`lib/services/holiday_service.dart`** — pure-data holiday catalog
  with fixed dates (Christmas, Valentine's, etc.), per-year special
  dates (Mardi Gras, Chinese New Year), and rule-based floating
  holidays (MLK Day, Easter via Gauss/Butcher, Thanksgiving). Also
  exposes per-month accent colors and per-holiday icon overrides
- **`lib/providers/calendar_provider.dart`** — `CalendarNotifier`
  fetches events in a wide window (12 months back, 24 months forward)
  on first load, plus the visible week range — so month scrubbing
  and week navigation don't trigger API calls. `setWeekOffset(offset)`
  shifts the week view; only out-of-window changes refetch
- **`lib/widgets/week_view.dart`** — shared 7-column week grid
  rendered in both card view and full-screen calendar. Merges Google
  events and tasks-with-due-dates from `dueTasksProvider` into one
  timeline per day. Today's column gets an accent-colored border.
  `compact: true` shrinks fonts/padding for the dashboard tile
- **`lib/widgets/calendar_card.dart`** — dashboard tile wrapping
  `WeekView`. Adds bobbing holiday icons, month-themed accent colors,
  and a `currentDateProvider` ticker that fires at midnight so the
  card repaints daily without a relaunch
- **`lib/screens/calendar_full_screen.dart`** — full-screen view with
  add-event modal, event-detail modal with delete option, and
  prev/next/today week navigation buttons

### Tasks & lists

- **`lib/services/lists_service.dart`** — persistence for the names
  of task lists (e.g. "To-do", "Shopping") in `lists.json` at the
  project root
- **`lib/database/database.dart`** Tasks table — `id`, `title`, `listName`,
  `priority`, `dueDate`, `completed`, `completedAt`
- **`lib/providers/tasks_provider.dart`** — `ListsNotifier` (the
  notifier behind `tasksProvider`) manages the active list, filter
  (active/completed/all), and a recently-completed tail capped at 6.
  Also exposes `dueTasksProvider` as a `StreamProvider` of every task
  with a due date — used by the calendar to merge tasks as
  pseudo-events
- **`lib/widgets/tasks_card.dart`** — dashboard tile with list tabs
  and up to 6 active items + 4 recently-completed
- **`lib/screens/tasks_full_screen.dart`** — full-screen view with
  list tabs, add/edit dialogs, due-date picker. The
  `showTaskEditDialog` function is reused for both add (when title
  isn't already typed) and edit

### Habits

- **`lib/database/database.dart`** Habits + HabitLogs tables —
  habits have `type` (`boolean` for checkbox or `numeric` for counter
  with target), `unit`, `color`, `sortOrder`, `archived` flag.
  HabitLogs is a unique-per-`(habitId, date)` log of values
- **`lib/providers/habits_provider.dart`** — `HabitsNotifier` loads
  active habits and a 28-day window of logs into a flat
  `'<habitId>_<date>' → value` map. `toggleLog(habit, date)` toggles
  or increments depending on type. `getStreak(habit)` walks backward
  from today and counts consecutive days completed
- **`lib/widgets/habits_card.dart`** — dashboard tile (currently
  invisible from the start menu, but the widget is built; HabitsCard
  was at one point rotated through `_cards`)
- **`lib/screens/habits_full_screen.dart`** — full-screen view with a
  7d/28d heatmap toggle, color-by-intensity completion grid, and a
  "+ Add Habit" modal

### OAuth & persistence

- **`lib/services/env_service.dart`** — reads `.env` from the project
  root. `Env.get(key)` returns the value or empty string
- **`lib/services/oauth_api_client.dart`** — abstract base class for
  OAuth-protected REST clients. Subclasses (Calendar, Spotify) provide
  service key, scopes, URLs, port, client ID/secret. Handles loopback
  auth (browser → callback → token exchange), token refresh (60s before
  expiry), and authed HTTP requests
- **`lib/services/oauth_service.dart`** — the loopback
  `HttpServer` itself. Binds to `127.0.0.1:port`, launches the
  browser via `cmd start` with a temp HTML redirect file (avoids URL
  escaping issues), waits for `/callback?code=...`. 5-minute timeout
- **`lib/database/database.dart` AuthTokens table** — stores
  `accessToken`, `refreshToken`, `expiry` keyed by service key
- **`lib/services/path_service.dart`** — resolves the project root
  by trying 5× `..` from the exe (release build), then `Directory.current`,
  then two hardcoded fallbacks. Convenience getters for assets/sub-dirs
- **`lib/services/gachadex_service.dart`** / `gachamon_game_service.dart` /
  `lists_service.dart` / `video_background_service.dart` — read/write
  their respective `*.json` files at the project root

### Audio visualizer & casting

- **`lib/services/visualizer_service.dart`** — `VisualizerNotifier`
  captures system audio via `desktop_audio_capture`, computes a 25-band
  FFT (simple bandwise sum, not a real FFT), and exposes `MiniVisualizer`
  — the rainbow bar widget used as background in the Spotify card
- **`lib/screens/visualizer_screen.dart`** — full-screen visualizer
  with throttled 30 fps updates, both bar and waveform painters
- **`lib/services/cast_service.dart`** — Chromecast discovery
  (Bonsoir mDNS for `_googlecast._tcp` services, resolves `.local` to
  IPv4) and casting via Cast V2 protocol over TLS (port 8009,
  self-signed certs, simplified protobuf with length prefix)

---

## Per-file reference

Files are grouped by directory. Each entry has the file's
responsibility, the public/important classes it exports, and the
important methods or top-level functions you might want to look up.

### `lib/main.dart`

**Responsibility:** App entry point. Initializes Env, video
backgrounds, gachadex, configures the borderless fullscreen window
(prefers secondary monitor), and renders `KitchenDashboardApp` with
the `YouTubeBackgroundPlayer` mounted in the `MaterialApp.builder`
beneath the `Navigator`.

**Key:**

- `main()` async — boot sequence
- `KitchenDashboardApp` — root widget; the `builder` `Stack` decides
  whether to render the YT background based on the active theme and
  `videoBackgroundEnabledProvider`
- `databaseProvider` — `Provider<AppDatabase>`
- `_MonitorFollowListener` — restores fullscreen sizing when the OS
  moves the window across displays

---

### `lib/database/`

#### `database.dart`

Drift schema (v3) and query interface.

- **Tables:** `Habits`, `HabitLogs` (unique on `habitId+date`),
  `Tasks`, `YoutubeChannels` (dormant), `AuthTokens`
- **`AppDatabase`** — Drift root with `MigrationStrategy` for v2
  (added `listName`) and v3 (added `completedAt`)
- **Habit queries:** `getActiveHabits()`, `getHabitLogs(start, end)`,
  `upsertHabitLog(habitId, date, value)`
- **Task queries:** `getTasks(filter, listName)`,
  `watchTasksWithDueDate()`
- **OAuth queries:** `getAuthToken(service)`, `saveAuthToken(entry)`

The `dashboard.db` file is locked while the exe runs; you must kill it
before rebuilding.

#### `database.g.dart`

Drift's generated code. Don't edit; regenerate with
`dart run build_runner build` if the schema changes.

---

### `lib/gachamon/gachamon_data.dart`

**Responsibility:** Gachamon model, rarity enum, weight table,
hand-curated seed list (Gen 1), global mutable `gachadex`.

- `Gachamon` — immutable record with `id`, `name`, `rarity`, `form?`,
  `type1`, `type2?`, `dexEntry?`, `category?`, `heightM?`, `weightKg?`,
  evolution links
- `GachamonRarity` — `common`, `uncommon`, `rare`, `pseudo`,
  `legendary`, `mythical`
- `Gachamon.uniqueKey` — `'<id>'` or `'<id>:<form>'` for alt forms
- `gachamonById(id)`, `gachamonByKey(uniqueKey)` — lookups
- `Gachamon.toJson` / `Gachamon.fromJson` — serialization for
  `gachadex.json`
- `rarityWeight` — map from `GachamonRarity` to draw weight
- `gachamonSpritePath(gachamon)` — disk path under `assets/gachamon/`
  selected by the form/generation

---

### `lib/providers/`

#### `effects_quality.dart`

The four-tier quality system. See [Effects quality system](#effects-quality-system).

- `EffectQuality` enum, `sparkleCount`, `stickersPerCard`, `label`
- `sparkleQualityProvider`, `stickerQualityProvider`,
  `videoBackgroundEnabledProvider`, `settingsPanelOpenProvider`

#### `calendar_provider.dart`

`CalendarNotifier` for Google Calendar.

- `CalendarState` — connection flag, events list, weekOffset
- `checkStatus()`, `connect()`, `disconnect()`
- `fetchEvents(monthOffset)` — wide pre-fetch (12m back, 24m forward)
- `setWeekOffset(offset)` — shift week view, refetch only on out-of-window
- `createEvent(summary, start, end, allDay)`,
  `deleteEvent(eventId)`

#### `tasks_provider.dart`

`ListsNotifier` for task lists.

- `ListsState` — active list, recently-completed tail (max 6),
  filter, available list names
- `fetchTasks()`, `setActiveList(name)`, `setFilter(filter)`,
  `addList(name)`
- `addTask(title, dueDate)`, `updateTaskFields(id, ...)`,
  `toggleTask(task)`, `deleteTask(id)`, `setDueDate(id, date)`
- `dueTasksProvider` — `StreamProvider<List<Task>>` of all tasks
  with a due date set, used by the calendar

#### `habits_provider.dart`

`HabitsNotifier` for habit tracking.

- `HabitsState` — active habits + log map keyed `'<habitId>_<date>'`
- `fetchAll(days)` — load habits + 28-day log window
- `toggleLog(habit, date)` — boolean toggle or numeric increment
- `addHabit(name, type, target, unit, color)`,
  `deleteHabit(id)` (soft-delete via archive)
- `getStreak(habit)` — backward day-walk

#### `spotify_provider.dart`

`SpotifyNotifier` for Spotify.

- `SpotifyState` — connected, player map, devices, playlists
- `connect()`, `disconnect()`, `checkStatus()`
- `_startPolling()` — 5-second loop while connected
- `play()`, `pause()`, `next()`, `previous()`, `seekTo(ms)`,
  `setVolume(percent)` — all swallow errors and add settle delays
- `transferPlayback(deviceId)`, `playTrack(uri)`,
  `playPlaylist(contextUri)`, `searchTracks(query)`, `getQueue()`

---

### `lib/screens/`

#### `dashboard_screen.dart`

The home screen. Owns the carousel/grid, drawer panels, theme
randomizer, sparkle/sticker generators, and start-menu wiring. See
[Dashboard screen](#dashboard-screen).

- `themeProvider` (`StateNotifierProvider<ThemeNotifier, DashboardTheme>`)
- `sparkleImagesProvider`, `graphicsImagesProvider` — placement state
- `gridModeProvider`, `stickerEditModeProvider`,
  `stickerPanelOpenProvider`, `stickerTabProvider`,
  `startMenuOpenProvider`, `bgPickerOpenProvider` — UI state providers
- `_cards` — list of `_CardDef` for the four dashboard tiles
- `ThemeNotifier.randomize()` — pick color/image/YT video; only includes
  YT when `videoBackgroundEnabledProvider == true`
- `shuffleEverything()` — full theme + overlays re-shuffle
- `_randomizeSparklesOnly`, `_randomizeGraphicsOnly` — quality-aware
  generators
- `_onSparkleQualityChanged`, `_onStickerQualityChanged` — instant
  re-render hooks for the Settings panel
- `_gachamonStickers(ref)`, `_holoSpritePaths(ref)`,
  `_stickersForTab(ref, tab)` — Gachamon-tab integration
- `_openFullScreen(context, screen)` — push a `ZoomInRoute`, play PC
  jingle for Gachamon
- `_buildStickerPanel`, `_buildBgPicker` — drawer content

#### `calendar_full_screen.dart`

Full-screen calendar — week grid, prev/today/next, add-event
modal, event-detail modal with delete.

- `_showAddDialog()` — modal for new events
- `_onEventTap(event)` — modal for event details

#### `tasks_full_screen.dart`

Full-screen list management — list tabs (with `+` to create),
add/edit dialogs, completed-task tail.

- `TaskEditResult` — return type for the edit modal
- `_TaskTile` — single task row
- `showTaskEditDialog(context, ...)` — reusable add-or-edit modal

#### `habits_full_screen.dart`

Full-screen habits — heatmap with 7d/28d toggle, color picker for
new habits, streak counts.

- `_showAddDialog()` — modal for new habits

#### `gachamon_full_screen.dart`

The gachapon screen — landscape (caught Gachamon), 151-slot Gachadex
grid, gachaball counter, catch dialog.

- `_GachamonFullScreenState._onCatch()` — opens `_CatchingDialog`
- `_GachadexGrid` — the 151-slot grid (private widget in the file)
- The catch dialog itself plays animations and reveals the gachamon

#### `spotify_full_screen.dart`

Spotify — search bar, playlist list, queue, embedded playlist
WebView (lazy — only created on click into a playlist).

- `_openSpotifyWeb({playlistId})` — creates the WebView with the
  audio-blocker script
- `_closeEmbed()` — disposes the WebView, restores playback to the
  previous device if it was hijacked

#### `visualizer_screen.dart`

Full-screen audio visualizer — FFT bars + waveform, throttled to
30 fps.

- `_startCapture()` — init `SystemAudioCapture`
- `_processAudio(data)` — int16 → 0-255 conversion + 25-band FFT

---

### `lib/services/`

#### `path_service.dart`

`PathService` static class. `projectRoot` getter does the 5-up walk
from the exe. Convenience getters: `assetsDir`, `backgroundsDir`,
`sparklesDir`, `graphicsDir`, `iconsDir`, `holidayIconsDir`, `envPath`.

#### `env_service.dart`

`Env` static class. `load()` reads `.env` from the project root.
`get(key)` returns the value or empty string.

#### `oauth_service.dart`

`OAuthLoopback.getAuthCode(authUrl, port)` — bind a local server,
launch the browser, wait for `/callback?code=...`. 5-minute timeout.

#### `oauth_api_client.dart`

`OAuthApiClient` abstract base. Subclasses implement abstract getters
for service key, URLs, scopes, etc.

- `isConnected()`, `connect()`, `disconnect()`
- `authedRequest(path, method, data, queryParams)` — adds Bearer
  token, auto-refreshes if within 60s of expiry
- `getAccessToken()` — refresh-if-needed accessor

#### `calendar_service.dart`

`CalendarService extends OAuthApiClient`. Port 8889.

- `getEvents(timeMin, timeMax)`, `createEvent(...)`,
  `deleteEvent(eventId)`

#### `spotify_service.dart`

`SpotifyService extends OAuthApiClient`. Port 8888.

- `getPlayer()`, `play()`, `pause()`, `next()`, `previous()`
- `setVolume(percent)`, `seekTo(ms)`
- `getDevices()`, `transferPlayback(deviceId)`, `getPlaylists()`,
  `searchTracks(query)`, `playTrack(uri)`, `playPlaylist(uri)`,
  `playTrackInContext(uri, contextUri)`

#### `spotify_webview.dart`

`SpotifyWebView` static helpers for the embedded WebView.

- `createAudioBlocked(url)` — initializes a controller with the
  audio-blocker script that mutes/pauses every `<audio>`/`<video>`
  on a 500 ms loop and replaces `AudioContext` with a no-op shim
- `scrollAt(controller, pos, dy)` — forwards mouse-wheel scrolls to
  the nearest scrollable ancestor under the pointer

#### `gachamon_game_service.dart`

`GachamonGameNotifier` (`gachamonGameProvider`). State persisted to
`gachamon_game.json`.

- `GachamonGameState` — `gachaballs`, `lastEarnHour`, `caught`,
  `holo`, `catchOrder`
- `spendBallAndCatch()` — gachapon roll with rarity weight,
  duplicate-protect, 5% holo
- `_accrueHourlyBalls()` — catch-up aware hourly grant
- `_load()`, `_save()` — JSON persistence

#### `gachadex_service.dart`

`GachadexService.load()` — read `gachadex.json` (seed from
`seedGachadex` if missing/corrupt), replace global `gachadex` list.

#### `lists_service.dart`

`ListsService.load()` and `save(names)` — `lists.json` at project
root. Defaults: `['To-do', 'Shopping']`.

#### `holiday_service.dart`

Pure data + functions.

- `holidaysFor(date)` — merge fixed-date, per-year, and floating
  rules; returns list of holiday names
- `monthColors[month]` — accent color per month for calendar
- Internal helpers: `_nthWeekday`, `_lastWeekday`, `_easterSunday`
  (Gauss/Butcher)

#### `video_background_service.dart`

`VideoBackgroundService.load()` — read `video_backgrounds.json`,
extract video IDs, fetch missing title/duration/aspectRatio via the
YouTube API, write enriched JSON back. `_videos` getter returns the
list.

#### `visualizer_service.dart`

`VisualizerNotifier` and `MiniVisualizer` widget.

- `VisualizerState` — `fft`, `waveform`, `active`
- `_start()` — init `SystemAudioCapture`, 50ms update timer
- `_process(data)` — int16 → 0-255 waveform + 25-band FFT
  (5× amplification, clamped)
- `MiniVisualizer` — animated rainbow bars rendered with a sweeping
  HSL color rotation

#### `cast_service.dart`

`CastDevice` data class and `CastService` for Chromecast.

- `discoverDevices(timeout)` — Bonsoir mDNS for `_googlecast._tcp`,
  resolve `.local`, return list
- `castYouTubeVideo(device, videoId)` — TLS to port 8009, launch
  YouTube app, wait for transportId, send `flingVideo` and `LOAD`

---

### `lib/theme/`

#### `app_colors.dart`

Static color tokens (semantic, not Win95). `bg`, `surface`, `border`,
`text`, `textMuted`, `accent`, plus tints (`green`, `red`, etc.) and
layout constants (`radius`, `radiusSm`, `minTapTarget`).
`textShadow` for readability on pastel backgrounds.

#### `app_theme.dart`

`AppTheme.dark()` returns a Material `ThemeData` composed from
`AppColors`. Only dark mode. Font: Segoe UI.

#### `animated_backgrounds.dart`

`DashboardTheme` data class, `themePalette` (10 pastels),
`getBackgroundImages()` (disk enumeration), and `AnimatedBackground`
widget (color/image/placeholder).

- `YouTubeBackground` data class — `videoId`, `title`,
  `durationSeconds`, `aspectRatio`
- `youtubeBackgrounds` getter — proxies `VideoBackgroundService.videos`
- `randomAccent()` — pick from palette

---

### `lib/widgets/`

#### `win95.dart`

The Win95 design system. See [Win95 design system](#win95-design-system).

- `Win95` static class, `Win95TitleBar`, `Win95TitleButton`,
  `Win95Panel`, `Win95InsetPanel`, `Win95Button`
- Border factories: `raisedBorder`, `sunkenBorder`,
  `pressableBorder`

#### `win95_taskbar.dart`

Bottom taskbar + start menu.

- `Win95Taskbar` — clock, Start button, active-window tab
- `Win95StartMenu` — vertical menu with Stickers, Change Background,
  Shuffle Theme, Grid/Carousel toggle, Settings, Exit

#### `dashboard_card.dart`

`DashboardCard` — reusable home tile with title bar + inset content
area. `colSpan`, `chromeOpacity`. Tap-to-open behavior wired via
`onTap`.

#### `full_screen_overlay.dart`

`FullScreenOverlay` — chrome shared by every full-screen route
(title bar, animated background, sparkle overlay, optional scroll).

- `ZoomInRoute` — page route with scale (0.85 → 1.0) + fade animation
- `SlideUpRoute` — page route with slide-up

#### `calendar_card.dart`

Dashboard tile for the calendar. Embeds `WeekView(compact: true)`,
adds bobbing holiday icons and month-themed accent colors.

- `currentDateProvider` — `StateNotifierProvider<DateTime>` ticking
  on day rollover
- `_BobbingIcon` — bob animation for holiday icons (seeded so the
  grid doesn't synchronize)

#### `week_view.dart`

Shared 7-column week grid for both card view and full screen. Merges
Google events from `calendarProvider` with tasks from
`dueTasksProvider` into per-day timelines. Today's column gets an
accent border. `compact` flag for card view.

- `_DayItem` — internal row wrapper

#### `tasks_card.dart`

Dashboard tile for lists — list tabs, up to 6 active items + 4
recently-completed items.

#### `habits_card.dart`

Dashboard tile for habits — up to 6 active habits with today's
checkbox (boolean) or progress indicator (numeric).

#### `spotify_card.dart`

Dashboard tile for Spotify — spinning CD album art (rotating
annular `ClipPath` with iridescent sweep gradient overlay), track
title, artists, play/pause/next/prev.

- `_SpinningCD` — rotating CD widget with `AnimationController`
- `_CDClipper` — `CustomClipper<Path>` for annulus shape

#### `gachamon_card.dart`

Dashboard tile for the Gachamon game — rendered as a spiral-bound
notebook page with a smattering of caught gachamon.

- `_Smattering` — caps at 20 sprites, content-addressed sample seed
  for stable selection across rebuilds, sprite size 70–110 px
- `_SpiralBindingPainter` — paints the metal binding rings (back +
  front halves so they read as 3D coils)
- `_SquiggleBorderPainter` — sine-wave decorative border

#### `gachadex_card.dart`

Single-Gachamon card display (~1000 lines). Rarity-tier borders,
mythical animated rainbow gradient via `HoloClock`, evolution chain
sprites, type icons, dex entry.

- `GachadexCard` — wraps `_GachadexCardState` which post-frame measures
  the card height for precise gradient math on mythical borders
- `_typeBackground(gachamon)` — gradient based on type1/type2

#### `gachadex_card_effects.dart`

Painter widgets for blinking star sparkles.

- `FillSparkles` — rectangular area
- `RingSparkles` — around a ring
- `_drawFourPointStar` — star shape primitive
- Sparkle periods chosen as divisors of the 120-second holo clock so
  they sync rather than drift

#### `gachamon_landscape.dart`

`GachamonLandscape` — gradient sky + grass background, 3 procedural
clouds, caught gachamon positioned at stable seeded coordinates.

#### `holographic.dart`

`HoloClock` singleton + `HoloLayer` shimmer. Key memory win: one frame
callback for every holo widget in the app (vs. one per sticker before
the consolidation).

- `HoloClock.instance` — singleton
- `HoloClock.seconds` — monotonic time
- `HoloLayer` — wraps child with `srcATop` shimmer overlay
- `HoloPainter` — multiline blob using Lissajous curves (used both
  by `HoloLayer` and by `paintStickerToCanvas`)

#### `render_layers.dart`

Low-level compositing primitives.

- `SaveLayer` — `RenderObjectWidget` forcing a compositing layer so
  children blend with each other, not the background
- `BlendMask` — `RenderObjectWidget` applying a blend mode to child
  contents (multiply, overlay, lighten, etc.)

#### `sticker_layer.dart`

`DashboardStickerLayer` — single-painter implementation for all
dashboard stickers (graphics + Gachamon sprites), with hit zones
layered on top for drag/rotate/resize.

- `_DashboardStickerLayerState` — owns `_cache: Map<String, AnimatedFrame>`,
  one `HoloClock` listener for the whole layer, on-screen culling via
  `_visiblePaths()`, eviction on `didUpdateWidget`
- `_StickerLayerPainter.paint()` — Gachamon path goes through
  `paintStickerToCanvas` with a `saveLayer` for srcATop isolation;
  graphic path uses contain-fitted `drawImageRect`
- Hit zones use `ValueKey(s.path)` so Flutter keeps the correct
  `DraggableSticker` element alive across 60 fps rebuilds

#### `sticker_sprite.dart`

`StickerSprite` widget (used by Gachamon card smattering and gachamon
landscape) and `paintStickerToCanvas` (used by the sticker layer's
Gachamon path).

- `paintStickerToCanvas(canvas, image, size, ...)` — paints multi-stamp
  white outline, sprite, optional holo aura. Caller MUST wrap in a
  `canvas.saveLayer()` for srcATop blend isolation
- `StickerSprite` — wraps `paintStickerToCanvas` in a `SaveLayer`
  widget for the same isolation when used standalone

#### `sticker_panel_widgets.dart`

`StickerTabs` (Win95 tabs for Graphics/Gachamon) and `BobbingSticker`
(sine-bob animation with hashed phase so a grid doesn't synchronize).
Also `DraggableSticker` — gesture wrapper with onDrag/onRotate/onResize.

#### `sparkle_layer.dart`

`SparkleLayer` — single-painter implementation for the dashboard
sparkle field. See [Sparkle layer](#sparkle-layer).

- `_SparkleLayerState` — `_cache`, `Ticker`, `_loadImage`,
  `_evictStale`, `_clearCache`
- `_SparkleLayerPainter.paint()` — draws every sparkle in one pass

#### `sparkle_overlay.dart`

Deprecated per-sparkle widget version. Still used by
`FullScreenOverlay` (for full-screen routes) but not by the dashboard.

- `OverlayImage` — simple `Image.file` wrapper used by the sticker
  drawer's previews
- `SparkleOverlay` — per-sparkle `Image.file` widgets in a `Stack`,
  conditional on `sparkleQualityProvider != off`

#### `animated_frame.dart`

Shared image container used by both `SparkleLayer` and
`DashboardStickerLayer`.

- `AnimatedFrame.load(path, targetWidth, targetHeight)` — preserves
  aspect ratio via `ImageDescriptor.encoded`, never upscales,
  disposes the codec immediately for static images
- `tick(delta)`, `advance(onDone)` — animated GIF/APNG cycling
- `dispose()` — disposes both `current` image and `_liveCodec`

#### `youtube_background.dart`

`YouTubeBackgroundPlayer` — runs a tiny local HTTP server serving a
custom HTML page with the YouTube IFrame Player API embed. Page does
its own BoxFit.cover math in JavaScript so the video fills the
screen.

- `_init()` — `HttpServer.bind` + `WebviewController.initialize`
- `dispose()` — closes the server and disposes the controller
- `_buildHtml()` — generates the embed HTML with
  `mute=1, controls=0, loop=1, playsinline=1`, etc.

#### `settings_panel.dart`

`SettingsPanel` — drawer that opens from the start menu. Three
labelled rows of effect quality controls.

- `_QualityRow` — 4-segment off/low/med/max picker (sparkles, stickers)
- `_BoolRow` — 2-segment On/Off toggle (video background)
- `_QualityButton` — pressable Win95-bevel button used by both rows

---

## Notes on memory and performance

For the full catalog of runtime optimizations and the design
decisions behind them, see
[Design decisions and runtime optimizations](#design-decisions-and-runtime-optimizations)
above. That section is the single source of truth for *why* the
architecture is shaped the way it is — what problem each
optimization solves, what tradeoffs it carries, and which files
implement it.

Quick mental model:

- **Per-frame work scales with what's on screen, not what's loaded.**
  The dex grid is lazy. The sticker layer culls off-screen items.
  Sparkle and sticker counts are user-controlled tiers (off / low /
  med / max).
- **Image decoding is centralized.** `AnimatedFrame` for sparkles
  and stickers; Flutter's `imageCache` for everything else. Both
  caches are pre-warmed where it matters (Gachamon sprites on dex
  full-screen entry) and aggressively shared across consumers.
- **Outline rendering is amortized.** The 17-stamp outline pipeline
  is baked once per (path, size, radius) tuple into a `ui.Image`
  via `StickerBakeCache`, then drawn back as a single
  `drawImageRect`.
- **Heavy subsystems are mounted lazily.** The YouTube background's
  WebView2 process only runs when a video is the active background;
  Spotify's playlist WebView only runs when you click into a
  playlist.

The `effectsQuality` providers are in-memory only and reset to
their defaults on app launch — by design, so a fresh boot is always
in a known state. Adding Drift-backed persistence would mirror the
`AuthTokens` pattern.
