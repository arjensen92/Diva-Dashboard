import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_windows/webview_windows.dart';
import '../theme/app_colors.dart';
import '../widgets/full_screen_overlay.dart';
import '../widgets/oauth_setup_dialog.dart';
import '../widgets/win95.dart';
import '../providers/spotify_provider.dart';
import '../services/spotify_webview.dart';
import '../services/visualizer_service.dart';

// Spotify dark colors
const _spotifyBlack = Color(0xFF121212);
const _spotifyDarkGray = Color(0xFF181818);
const _spotifyGray = Color(0xFF282828);
const _spotifyGreen = Color(0xFF1DB954);

class SpotifyFullScreen extends ConsumerStatefulWidget {
  const SpotifyFullScreen({super.key});
  @override
  ConsumerState<SpotifyFullScreen> createState() => _SpotifyFullScreenState();
}

class _SpotifyFullScreenState extends ConsumerState<SpotifyFullScreen> {
  final _searchController = TextEditingController();
  List<dynamic> _searchResults = [];
  double _volume = 50;
  bool _isDraggingVolume = false;
  double _seekPosition = 0;
  bool _isDraggingSeek = false;

  // Playlist detail view
  String? _openPlaylistId;
  String? _openPlaylistName;
  String? _openPlaylistUri;
  List<dynamic> _playlistTracks = [];
  bool _loadingTracks = false;
  String _trackFilter = '';

  // Embedded playlist browser
  String? _embedPlaylistId;
  WebviewController? _webviewController;
  bool _webviewReady = false;
  String? _previousDeviceId; // device to restore playback to when closing WebView

  @override
  void dispose() {
    _searchController.dispose();
    _webviewController?.dispose();
    super.dispose();
  }

  Offset _hoverPos = Offset.zero;

  Future<void> _openSpotifyWeb({String? playlistId}) async {
    // Remember current device so we can restore playback when closing.
    final state = ref.read(spotifyProvider);
    _previousDeviceId = state.player?['device']?['id'];

    setState(() {
      _embedPlaylistId = playlistId ?? 'browse';
      _webviewReady = false;
    });
    final url = playlistId != null
        ? 'https://open.spotify.com/playlist/$playlistId'
        : 'https://open.spotify.com';
    final controller = await SpotifyWebView.createAudioBlocked(url);
    setState(() {
      _webviewController = controller;
      _webviewReady = true;
    });
  }

  void _handleWebviewScroll(PointerScrollEvent event) {
    final controller = _webviewController;
    if (controller == null) return;
    SpotifyWebView.scrollAt(controller, _hoverPos, event.scrollDelta.dy);
  }

  void _closeEmbed() async {
    _webviewController?.dispose();
    setState(() {
      _embedPlaylistId = null;
      _webviewController = null;
      _webviewReady = false;
    });
    // If the web player somehow stole playback, transfer it back
    if (_previousDeviceId != null) {
      await Future.delayed(const Duration(milliseconds: 300));
      try {
        // Check if playback is still active
        final player = await ref.read(spotifyProvider.notifier).service.getPlayer();
        if (player == null || player['is_playing'] != true) {
          // Playback stopped — restore to previous device
          await ref.read(spotifyProvider.notifier).transferPlayback(_previousDeviceId!);
        }
      } catch (_) {}
      _previousDeviceId = null;
    }
  }

  Future<void> _search() async {
    final q = _searchController.text.trim();
    if (q.isEmpty) return;
    final results = await ref.read(spotifyProvider.notifier).searchTracks(q);
    setState(() => _searchResults = results);
  }

  Future<void> _playAndShowQueue(Map<String, dynamic> pl) async {
    setState(() {
      _openPlaylistId = pl['id'];
      _openPlaylistName = pl['name'];
      _openPlaylistUri = pl['uri'];
      _loadingTracks = true;
    });
    await ref.read(spotifyProvider.notifier).playPlaylist(pl['uri']);
    await Future.delayed(const Duration(milliseconds: 1000));
    final queue = await ref.read(spotifyProvider.notifier).getQueue();
    setState(() {
      _playlistTracks = queue;
      _loadingTracks = false;
    });
  }

  Future<void> _openQueue() async {
    setState(() {
      _openPlaylistId = 'queue';
      _openPlaylistName = 'Queue';
      _openPlaylistUri = null;
      _loadingTracks = true;
    });
    final queue = await ref.read(spotifyProvider.notifier).getQueue();
    setState(() {
      _playlistTracks = queue;
      _loadingTracks = false;
    });
  }

  Future<void> _refreshQueue() async {
    setState(() => _loadingTracks = true);
    await Future.delayed(const Duration(milliseconds: 300));
    final queue = await ref.read(spotifyProvider.notifier).getQueue();
    setState(() {
      _playlistTracks = queue;
      _loadingTracks = false;
    });
  }

  void _closePlaylist() {
    setState(() {
      _openPlaylistId = null;
      _playlistTracks = [];
      _trackFilter = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(spotifyProvider);

    if (!state.connected) {
      return FullScreenOverlay(
        title: 'Spotify',
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.music_note, size: 60, color: AppColors.textMuted),
              const SizedBox(height: 16),
              const Text('Connect Spotify to control playback', style: TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 4),
              const Text('Requires Spotify Premium', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  // Same setup-required guard as the calendar screen:
                  // without populated env vars, connect() returns false
                  // silently and the button looks broken. Surface a
                  // clear dialog instead.
                  final svc =
                      ref.read(spotifyProvider.notifier).service;
                  if (!svc.isConfigured) {
                    await showOAuthSetupRequiredDialog(
                      context,
                      serviceName: 'Spotify',
                      envVarNames: const [
                        'SPOTIFY_CLIENT_ID',
                        'SPOTIFY_CLIENT_SECRET',
                      ],
                      credentialUrl:
                          'https://developer.spotify.com/dashboard  (create an app, '
                          'add http://127.0.0.1:8888/callback as a redirect URI, '
                          'and copy the Client ID + Client Secret)',
                      credentialUrlLabel:
                          'Spotify Developer Dashboard',
                    );
                    return;
                  }
                  ref.read(spotifyProvider.notifier).connect();
                },
                child: const Text('Connect Spotify'),
              ),
            ],
          ),
        ),
      );
    }

    final track = state.track;
    final albumArt = track != null && (track['album']?['images'] as List?)?.isNotEmpty == true
        ? track['album']['images'][0]['url']
        : null;
    final artists = track != null ? (track['artists'] as List?)?.map((a) => a['name']).join(', ') ?? '' : '';

    // Sync volume with player only when not dragging
    if (!_isDraggingVolume && state.player?['device']?['volume_percent'] != null) {
      final playerVol = (state.player!['device']['volume_percent'] as num).toDouble();
      _volume = playerVol;
    }

    // If viewing a playlist detail
    // Spotify web player view
    if (_embedPlaylistId != null) {
      return _buildEmbedView();
    }

    // Queue view
    if (_openPlaylistId != null) {
      return _buildPlaylistDetail(state);
    }

    return FullScreenOverlay(
      title: 'Spotify',
      child: Column(
        children: [
          // Now playing — with visualizer behind album art
          ClipRRect(
            borderRadius: BorderRadius.circular(AppColors.radius),
            child: SizedBox(
              width: 200, height: 200,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      color: Colors.black,
                      child: const Opacity(opacity: 0.7, child: MiniVisualizer(height: double.infinity)),
                    ),
                  ),
                  if (albumArt != null)
                    Positioned.fill(child: Opacity(opacity: 0.65, child: Image.network(albumArt, fit: BoxFit.cover))),
                ],
              ),
            ),
          ),
          if (track != null) ...[
            const SizedBox(height: 16),
            Text(track['name'] ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(artists, style: const TextStyle(fontSize: 16, color: AppColors.textMuted), textAlign: TextAlign.center),
          ] else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Text('Nothing playing', style: TextStyle(color: AppColors.textMuted)),
            ),

          // Controls with semi-transparent background
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(AppColors.radius),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(onPressed: () => ref.read(spotifyProvider.notifier).previous(), icon: const Icon(Icons.skip_previous, size: 32, color: Colors.white), constraints: const BoxConstraints(minWidth: 48, minHeight: 48)),
                const SizedBox(width: 12),
                Container(
                  width: 56, height: 56,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: _spotifyGreen),
                  child: IconButton(
                    onPressed: () => state.isPlaying ? ref.read(spotifyProvider.notifier).pause() : ref.read(spotifyProvider.notifier).play(),
                    icon: Icon(state.isPlaying ? Icons.pause : Icons.play_arrow, size: 32, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(onPressed: () => ref.read(spotifyProvider.notifier).next(), icon: const Icon(Icons.skip_next, size: 32, color: Colors.white), constraints: const BoxConstraints(minWidth: 48, minHeight: 48)),
              ],
            ),
          ),

          // Track seek bar
          Builder(builder: (_) {
            final progressMs = (!_isDraggingSeek && state.player?['progress_ms'] != null)
                ? (state.player!['progress_ms'] as num).toDouble()
                : _seekPosition;
            final durationMs = (track?['duration_ms'] as num?)?.toDouble() ?? 1;
            final pos = _isDraggingSeek ? _seekPosition : progressMs;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Column(
                children: [
                  SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: _spotifyGreen,
                      thumbColor: Colors.white,
                      inactiveTrackColor: _spotifyGray,
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    ),
                    child: Slider(
                      value: pos.clamp(0, durationMs),
                      min: 0,
                      max: durationMs,
                      onChanged: (v) => setState(() { _seekPosition = v; _isDraggingSeek = true; }),
                      onChangeEnd: (v) {
                        ref.read(spotifyProvider.notifier).seekTo(v.round());
                        setState(() => _isDraggingSeek = false);
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_formatDuration(pos.round()), style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                        Text(_formatDuration(durationMs.round()), style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),

          // Volume — smaller, below seek
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 0),
            child: Row(
              children: [
                const Icon(Icons.volume_down, color: AppColors.textMuted, size: 16),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: Colors.white54,
                      thumbColor: Colors.white,
                      inactiveTrackColor: _spotifyGray,
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                    ),
                    child: Slider(
                      value: _volume.clamp(0, 100),
                      min: 0, max: 100,
                      onChanged: (v) => setState(() { _volume = v; _isDraggingVolume = true; }),
                      onChangeEnd: (v) {
                        ref.read(spotifyProvider.notifier).setVolume(v.round());
                        setState(() => _isDraggingVolume = false);
                      },
                    ),
                  ),
                ),
                const Icon(Icons.volume_up, color: AppColors.textMuted, size: 16),
              ],
            ),
          ),

          // === Spotify dark section ===
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _spotifyBlack,
              borderRadius: BorderRadius.circular(AppColors.radius),
            ),
            child: Column(
              children: [
                // Devices
                _sectionTitle('Devices'),
                ...state.devices.map((d) {
                  final isActive = d['is_active'] == true;
                  final deviceType = d['type'] ?? 'Computer';
                  final icon = deviceType == 'Speaker' ? Icons.speaker : deviceType == 'Smartphone' ? Icons.smartphone : Icons.computer;
                  return GestureDetector(
                    onTap: () => ref.read(spotifyProvider.notifier).transferPlayback(d['id']),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppColors.radiusSm),
                        border: Border.all(color: isActive ? _spotifyGreen : _spotifyGray),
                        color: isActive ? _spotifyGreen.withValues(alpha: 0.12) : _spotifyDarkGray,
                      ),
                      child: Row(
                        children: [
                          Icon(icon, size: 20, color: isActive ? _spotifyGreen : Colors.white70),
                          const SizedBox(width: 12),
                          Expanded(child: Text(d['name'] ?? '', style: const TextStyle(color: Colors.white))),
                          if (isActive) const Text('Active', style: TextStyle(fontSize: 12, color: _spotifyGreen)),
                        ],
                      ),
                    ),
                  );
                }),
                if (state.devices.isEmpty)
                  const Text('No devices found. Open Spotify on a device.', style: TextStyle(color: Colors.white38, fontSize: 14)),

                // Search
                _sectionTitle('Search'),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Search for a song...',
                          hintStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: _spotifyGray,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppColors.radiusSm), borderSide: BorderSide.none),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppColors.radiusSm), borderSide: BorderSide.none),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppColors.radiusSm), borderSide: const BorderSide(color: _spotifyGreen)),
                        ),
                        onSubmitted: (_) => _search(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _search,
                      style: ElevatedButton.styleFrom(backgroundColor: _spotifyGreen),
                      child: const Text('Search'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ..._searchResults.map((t) {
                  final img = (t['album']?['images'] as List?)?.isNotEmpty == true ? t['album']['images'].last['url'] : null;
                  return GestureDetector(
                    onTap: () => ref.read(spotifyProvider.notifier).playTrack(t['uri']),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                      margin: const EdgeInsets.only(bottom: 2),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
                      child: Row(
                        children: [
                          if (img != null) ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.network(img, width: 44, height: 44, fit: BoxFit.cover)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t['name'] ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                                Text((t['artists'] as List?)?.map((a) => a['name']).join(', ') ?? '', style: const TextStyle(fontSize: 12, color: Colors.white54)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),

                // Quick actions
                _sectionTitle('Now Playing'),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _openQueue(),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _spotifyGray,
                            borderRadius: BorderRadius.circular(AppColors.radiusSm),
                            border: Border.all(color: _spotifyGreen.withValues(alpha: 0.3)),
                          ),
                          child: const Column(
                            children: [
                              Icon(Icons.queue_music, color: _spotifyGreen, size: 28),
                              SizedBox(height: 6),
                              Text('Queue', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _openSpotifyWeb(),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _spotifyGray,
                            borderRadius: BorderRadius.circular(AppColors.radiusSm),
                            border: Border.all(color: _spotifyGreen.withValues(alpha: 0.3)),
                          ),
                          child: const Column(
                            children: [
                              Icon(Icons.open_in_new, color: _spotifyGreen, size: 28),
                              SizedBox(height: 6),
                              Text('Browse Spotify', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Playlists
                _sectionTitle('Your Playlists'),
                ...state.playlists.map((pl) {
                  final img = (pl['images'] as List?)?.isNotEmpty == true ? pl['images'][0]['url'] : null;
                  return GestureDetector(
                    onTap: () => _openSpotifyWeb(playlistId: pl['id']),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                      margin: const EdgeInsets.only(bottom: 2),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
                      child: Row(
                        children: [
                          if (img != null)
                            ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.network(img, width: 48, height: 48, fit: BoxFit.cover))
                          else
                            Container(width: 48, height: 48, decoration: BoxDecoration(color: _spotifyGray, borderRadius: BorderRadius.circular(4)), child: const Icon(Icons.music_note, color: Colors.white38)),
                          const SizedBox(width: 12),
                          Expanded(child: Text(pl['name'] ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.white))),
                          const Icon(Icons.play_circle_outline, color: Colors.white38, size: 24),
                        ],
                      ),
                    ),
                  );
                }),

                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: () => ref.read(spotifyProvider.notifier).disconnect(),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.red, side: BorderSide(color: AppColors.red.withValues(alpha: 0.3))),
                  child: const Text('Disconnect Spotify'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // === Playlist Detail View ===
  Widget _buildPlaylistDetail(SpotifyState state) {
    final filterLower = _trackFilter.toLowerCase();
    final filtered = _trackFilter.isEmpty
        ? _playlistTracks
        : _playlistTracks.where((t) {
            final name = (t['name'] ?? '').toString().toLowerCase();
            final artists = ((t['artists'] as List?)?.map((a) => a['name']).join(', ') ?? '').toLowerCase();
            return name.contains(filterLower) || artists.contains(filterLower);
          }).toList();

    return FullScreenOverlay(
      title: _openPlaylistName ?? 'Playlist',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top controls row
          Row(
            children: [
              GestureDetector(
                onTap: _closePlaylist,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  decoration: BoxDecoration(color: _spotifyGray, borderRadius: BorderRadius.circular(AppColors.radiusSm)),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back, size: 18, color: Colors.white70),
                      SizedBox(width: 8),
                      Text('Back', style: TextStyle(color: Colors.white70, fontSize: 14)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _refreshQueue,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Search/filter within queue
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: _spotifyBlack, borderRadius: BorderRadius.circular(AppColors.radius)),
            child: Column(
              children: [
                // Filter bar
                TextField(
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Filter tracks...',
                    hintStyle: const TextStyle(color: Colors.white38),
                    prefixIcon: const Icon(Icons.search, color: Colors.white38),
                    filled: true,
                    fillColor: _spotifyGray,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppColors.radiusSm), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppColors.radiusSm), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppColors.radiusSm), borderSide: const BorderSide(color: _spotifyGreen)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onChanged: (v) => setState(() => _trackFilter = v),
                ),
                const SizedBox(height: 12),

                if (_loadingTracks)
                  const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: _spotifyGreen)))
                else if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(40),
                    child: Text(
                      _trackFilter.isEmpty ? 'No tracks in queue' : 'No matches for "$_trackFilter"',
                      style: const TextStyle(color: Colors.white38),
                    ),
                  )
                else ...[
                  Text('${filtered.length} tracks', style: const TextStyle(color: Colors.white38, fontSize: 13)),
                  const SizedBox(height: 8),
                  ...filtered.asMap().entries.map((entry) {
                    final i = entry.key;
                    final t = entry.value;
                    final img = (t['album']?['images'] as List?)?.isNotEmpty == true ? t['album']['images'].last['url'] : null;
                    final isCurrentTrack = state.track?['id'] == t['id'];
                    return GestureDetector(
                      onTap: () => ref.read(spotifyProvider.notifier).playTrack(t['uri']),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                        decoration: BoxDecoration(
                          color: isCurrentTrack ? _spotifyGreen.withValues(alpha: 0.15) : null,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            SizedBox(width: 28, child: Text('${i + 1}', style: TextStyle(color: isCurrentTrack ? _spotifyGreen : Colors.white38, fontSize: 13), textAlign: TextAlign.center)),
                            const SizedBox(width: 10),
                            if (img != null) ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.network(img, width: 40, height: 40, fit: BoxFit.cover)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(t['name'] ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: isCurrentTrack ? _spotifyGreen : Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  Text((t['artists'] as List?)?.map((a) => a['name']).join(', ') ?? '', style: const TextStyle(fontSize: 12, color: Colors.white54), maxLines: 1, overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                            if (t['duration_ms'] != null)
                              Text(_formatDuration(t['duration_ms']), style: const TextStyle(fontSize: 12, color: Colors.white38)),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmbedView() {
    return Scaffold(
      backgroundColor: _spotifyBlack,
      body: Column(
        children: [
          Win95TitleBar(
            title: 'Playlist',
            titleFontSize: 16,
            buttonSize: 44,
            onClose: _closeEmbed,
          ),
          // WebView fills the rest
          Expanded(
            child: _webviewReady && _webviewController != null
                ? MouseRegion(
                    onHover: (event) => _hoverPos = event.localPosition,
                    child: Listener(
                      onPointerSignal: (event) {
                        if (event is PointerScrollEvent) {
                          _handleWebviewScroll(event);
                        }
                      },
                      child: Webview(_webviewController!),
                    ),
                  )
                : const Center(child: CircularProgressIndicator(color: _spotifyGreen)),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int ms) {
    final minutes = (ms ~/ 60000);
    final seconds = ((ms % 60000) ~/ 1000);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title.toUpperCase(),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white54, letterSpacing: 0.5),
        ),
      ),
    );
  }
}
