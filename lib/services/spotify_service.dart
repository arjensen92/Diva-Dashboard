import '../database/database.dart';
import 'env_service.dart';
import 'oauth_api_client.dart';

/// Spotify Web API client. Inherits OAuth plumbing from
/// [OAuthApiClient]; this class adds player / playlist / search
/// endpoints.
class SpotifyService extends OAuthApiClient {
  static const _authBase = 'https://accounts.spotify.com';
  static const _port = 8888;
  static const _scopes = [
    'user-read-playback-state',
    'user-modify-playback-state',
    'user-read-currently-playing',
    'playlist-read-private',
    'playlist-read-collaborative',
    'user-library-read',
    'streaming',
  ];

  SpotifyService(AppDatabase db) : super(db: db);

  @override
  String get serviceKey => 'spotify';
  @override
  String get logTag => 'Spotify';
  @override
  String get apiBaseUrl => 'https://api.spotify.com/v1';
  @override
  String get tokenUrl => '$_authBase/api/token';
  @override
  String get clientId => Env.get('SPOTIFY_CLIENT_ID');
  @override
  String get clientSecret => Env.get('SPOTIFY_CLIENT_SECRET');
  @override
  int get redirectPort => _port;
  @override
  String get authorizationUrl =>
      '$_authBase/authorize?response_type=code'
      '&client_id=$clientId'
      '&scope=${Uri.encodeComponent(_scopes.join(' '))}'
      '&redirect_uri=${Uri.encodeComponent(redirectUri)}';

  // === Player ===
  Future<Map<String, dynamic>?> getPlayer() async {
    try {
      final resp = await authedRequest('/me/player');
      if (resp.statusCode == 204) return null;
      return resp.data;
    } catch (_) {
      return null;
    }
  }

  Future<void> play() async {
    try { await authedRequest('/me/player/play', method: 'PUT'); }
    catch (e) { print('[Spotify] play error: $e'); }
  }
  Future<void> pause() async {
    try { await authedRequest('/me/player/pause', method: 'PUT'); }
    catch (e) { print('[Spotify] pause error: $e'); }
  }
  Future<void> next() async {
    try { await authedRequest('/me/player/next', method: 'POST'); }
    catch (e) { print('[Spotify] next error: $e'); }
  }
  Future<void> previous() async {
    try { await authedRequest('/me/player/previous', method: 'POST'); }
    catch (e) { print('[Spotify] previous error: $e'); }
  }

  Future<void> setVolume(int percent) =>
      authedRequest('/me/player/volume?volume_percent=$percent', method: 'PUT');

  Future<void> seekTo(int positionMs) =>
      authedRequest('/me/player/seek?position_ms=$positionMs', method: 'PUT');

  Future<void> transferPlayback(String deviceId) =>
      authedRequest('/me/player',
          method: 'PUT', data: {'device_ids': [deviceId], 'play': true});

  // === Devices ===
  Future<List<dynamic>> getDevices() async {
    try {
      final resp = await authedRequest('/me/player/devices');
      return resp.data['devices'] ?? [];
    } catch (_) {
      return [];
    }
  }

  // === Search ===
  Future<List<dynamic>> searchTracks(String query) async {
    try {
      final resp = await authedRequest(
          '/search?q=${Uri.encodeComponent(query)}&type=track&limit=10');
      return resp.data['tracks']?['items'] ?? [];
    } catch (_) {
      return [];
    }
  }

  Future<void> playTrack(String uri) async {
    try {
      await authedRequest('/me/player/play',
          method: 'PUT', data: {'uris': [uri]});
    } catch (e) {
      print('[Spotify] playTrack error: $e');
    }
  }

  // === Playlists ===
  Future<List<dynamic>> getPlaylists() async {
    try {
      final resp = await authedRequest(
          '/me/playlists?limit=50&fields=items(id,name,uri,images,tracks.total)');
      final items = resp.data['items'] as List? ?? [];
      if (items.isNotEmpty) {
        print('[Spotify] Playlist[0]: ${items[0]['name']}, tracks: ${items[0]['tracks']}');
      }
      return items;
    } catch (e) {
      print('[Spotify] getPlaylists error: $e');
      // Fallback without fields filter — some accounts return 400 when
      // requesting the fields mask.
      try {
        final resp = await authedRequest('/me/playlists?limit=50');
        return resp.data['items'] as List? ?? [];
      } catch (_) {
        return [];
      }
    }
  }

  Future<void> playPlaylist(String contextUri) async {
    try {
      await authedRequest('/me/player/play',
          method: 'PUT', data: {'context_uri': contextUri});
    } catch (e) {
      print('[Spotify] playPlaylist error: $e');
    }
  }

  // === Queue (workaround for playlist tracks — Spotify blocks track listing for unverified apps) ===
  Future<List<dynamic>> getQueue() async {
    try {
      final resp = await authedRequest('/me/player/queue');
      final queue = resp.data['queue'] as List? ?? [];
      print('[Spotify] Queue has ${queue.length} tracks');
      return queue;
    } catch (e) {
      print('[Spotify] Error fetching queue: $e');
      return [];
    }
  }

  Future<void> playTrackInContext(String trackUri, String contextUri) =>
      authedRequest('/me/player/play',
          method: 'PUT',
          data: {'context_uri': contextUri, 'offset': {'uri': trackUri}});
}
