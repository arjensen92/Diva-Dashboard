import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/spotify_service.dart';
import '../main.dart';

class SpotifyState {
  final bool connected;
  final Map<String, dynamic>? player;
  final List<dynamic> devices;
  final List<dynamic> playlists;
  SpotifyState({this.connected = false, this.player, this.devices = const [], this.playlists = const []});

  bool get isPlaying => player?['is_playing'] == true;
  Map<String, dynamic>? get track => player?['item'];
}

class SpotifyNotifier extends StateNotifier<SpotifyState> {
  final SpotifyService service;
  Timer? _pollTimer;

  SpotifyNotifier(this.service) : super(SpotifyState()) {
    checkStatus();
  }

  Future<void> checkStatus() async {
    final connected = await service.isConnected();
    state = SpotifyState(connected: connected);
    if (connected) {
      await _fetchAll();
      _startPolling();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchPlayer());
  }

  Future<void> _fetchAll() async {
    final player = await service.getPlayer();
    final devices = await service.getDevices();
    final playlists = await service.getPlaylists();
    if (mounted) {
      state = SpotifyState(connected: true, player: player, devices: devices, playlists: playlists);
    }
  }

  Future<void> _fetchPlayer() async {
    if (!state.connected) return;
    final player = await service.getPlayer();
    if (mounted) {
      state = SpotifyState(connected: true, player: player, devices: state.devices, playlists: state.playlists);
    }
  }

  Future<void> connect() async {
    final ok = await service.connect();
    if (ok) await checkStatus();
  }

  Future<void> disconnect() async {
    _pollTimer?.cancel();
    await service.disconnect();
    state = SpotifyState(connected: false);
  }

  Future<void> play() async { try { await service.play(); } catch(_) {} await Future.delayed(const Duration(milliseconds: 300)); await _fetchPlayer(); }
  Future<void> pause() async { try { await service.pause(); } catch(_) {} await Future.delayed(const Duration(milliseconds: 300)); await _fetchPlayer(); }
  Future<void> next() async { await service.next(); await Future.delayed(const Duration(milliseconds: 300)); await _fetchPlayer(); }
  Future<void> previous() async { await service.previous(); await Future.delayed(const Duration(milliseconds: 300)); await _fetchPlayer(); }
  Future<void> setVolume(int percent) => service.setVolume(percent);
  Future<void> seekTo(int positionMs) => service.seekTo(positionMs);
  Future<void> transferPlayback(String deviceId) async {
    await service.transferPlayback(deviceId);
    await Future.delayed(const Duration(milliseconds: 500));
    await _fetchAll();
  }
  Future<void> playTrack(String uri) async {
    await service.playTrack(uri);
    await Future.delayed(const Duration(milliseconds: 500));
    await _fetchPlayer();
  }
  Future<void> playPlaylist(String contextUri) async {
    await service.playPlaylist(contextUri);
    await Future.delayed(const Duration(milliseconds: 500));
    await _fetchPlayer();
  }
  Future<List<dynamic>> searchTracks(String query) => service.searchTracks(query);
  Future<List<dynamic>> getQueue() => service.getQueue();
  Future<void> playTrackInContext(String trackUri, String contextUri) async {
    await service.playTrackInContext(trackUri, contextUri);
    await Future.delayed(const Duration(milliseconds: 500));
    await _fetchPlayer();
  }
  Future<void> refreshDevices() async {
    final devices = await service.getDevices();
    if (mounted) {
      state = SpotifyState(connected: true, player: state.player, devices: devices, playlists: state.playlists);
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

final spotifyServiceProvider = Provider<SpotifyService>((ref) {
  final db = ref.watch(databaseProvider);
  return SpotifyService(db);
});

final spotifyProvider = StateNotifierProvider<SpotifyNotifier, SpotifyState>((ref) {
  final service = ref.watch(spotifyServiceProvider);
  return SpotifyNotifier(service);
});
