import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../database/database.dart';
import 'oauth_service.dart';

/// Base class for OAuth-protected REST API clients (Google Calendar,
/// Spotify, …). Handles the boilerplate that was duplicated verbatim
/// across services: loopback auth, code-for-token exchange, storage,
/// auto-refresh on expiry, and authed request dispatch.
///
/// Subclasses fill in the per-service constants (endpoints, scopes,
/// client ID env vars, redirect port, AuthTokens service key) via
/// abstract getters. Everything else is inherited.
///
/// Call [authedRequest] from subclass methods rather than hitting [dio]
/// directly — it wires in the Authorization header and refreshes the
/// token first if needed.
abstract class OAuthApiClient {
  final AppDatabase db;

  /// Pre-configured Dio instance with `baseUrl` set to [apiBaseUrl].
  @protected
  final Dio dio;

  OAuthApiClient({required this.db}) : dio = Dio() {
    // Base URL is pulled from the subclass's [apiBaseUrl] getter, which
    // can't be referenced in the initializer list — set it in the body.
    dio.options.baseUrl = apiBaseUrl;
  }

  // ===== Per-service configuration (subclasses override) =====

  /// AuthTokens row key — e.g. `'google'`, `'spotify'`.
  String get serviceKey;

  /// REST API base URL — e.g. `'https://www.googleapis.com/calendar/v3'`.
  String get apiBaseUrl;

  /// Token endpoint for both the authorization-code and refresh-token
  /// grants — e.g. `'https://oauth2.googleapis.com/token'`.
  String get tokenUrl;

  /// Client ID from `.env`. Keep as a getter (not a field) so a missing
  /// `.env` value is flagged at use time rather than construction time.
  String get clientId;

  /// Client secret from `.env`.
  String get clientSecret;

  /// Port the local HTTP server binds to for the OAuth redirect. Must
  /// match the redirect URI registered with the provider.
  int get redirectPort;

  /// Fully-qualified authorization URL (with response_type, client_id,
  /// scopes, redirect_uri baked in) — subclasses build this so each
  /// provider can set its own scopes / extra params (`access_type`,
  /// `prompt`, etc.).
  String get authorizationUrl;

  /// Prefix for `[OAuth]`-style log lines — e.g. `'Calendar'`, `'Spotify'`.
  String get logTag;

  /// Derived redirect URI — what gets sent to the provider in both the
  /// auth URL and the token exchange.
  String get redirectUri => 'http://127.0.0.1:$redirectPort/callback';

  // ===== Public surface =====

  Future<bool> isConnected() async =>
      (await db.getAuthToken(serviceKey)) != null;

  Future<void> disconnect() => db.deleteAuthToken(serviceKey);

  /// True when both `clientId` and `clientSecret` resolve to non-empty
  /// strings (i.e. the user has populated the relevant entries in
  /// `<projectRoot>/.env`). Callers should check this before invoking
  /// [connect] and surface a clear setup-required message to the user
  /// when it returns false — otherwise [connect] just logs and bails
  /// silently, which looks like a broken button to the user.
  bool get isConfigured => clientId.isNotEmpty && clientSecret.isNotEmpty;

  /// Runs the browser loopback flow, exchanges the returned code for
  /// tokens, and persists them. Returns `false` if the user cancels,
  /// the `.env` is missing a client ID, or the token exchange fails.
  Future<bool> connect() async {
    if (clientId.isEmpty) {
      print('[$logTag] ERROR: clientId is empty. Check .env.');
      return false;
    }
    final code = await OAuthLoopback.getAuthCode(
        authUrl: authorizationUrl, port: redirectPort);
    if (code == null) return false;

    try {
      final resp = await Dio().post(
        tokenUrl,
        options: Options(contentType: Headers.formUrlEncodedContentType),
        data: {
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': redirectUri,
          'client_id': clientId,
          'client_secret': clientSecret,
        },
      );
      final data = resp.data;
      await _storeTokens(
          data['access_token'], data['refresh_token'], data['expires_in']);
      return true;
    } catch (e) {
      print('[$logTag] Token exchange failed: $e');
      return false;
    }
  }

  /// Makes an authenticated request against [apiBaseUrl]. Automatically
  /// refreshes the access token if it's within 60s of expiry. Throws if
  /// the user isn't connected (no stored token).
  @protected
  Future<Response> authedRequest(
    String path, {
    String method = 'GET',
    dynamic data,
    Map<String, dynamic>? queryParameters,
  }) async {
    final token = await getAccessToken();
    if (token == null) throw Exception('$logTag: not connected');
    return dio.request(
      path,
      queryParameters: queryParameters,
      data: data,
      options:
          Options(method: method, headers: {'Authorization': 'Bearer $token'}),
    );
  }

  /// Returns a fresh access token — either the stored one if still valid,
  /// or the result of refreshing. Returns `null` if no tokens are stored
  /// or the refresh call fails. Protected: subclasses may call this
  /// directly if they need raw token access for a non-[dio] request.
  @protected
  Future<String?> getAccessToken() async {
    final stored = await db.getAuthToken(serviceKey);
    if (stored == null) return null;

    final expiresAt = stored.expiresAt;
    final isExpired = expiresAt != null &&
        DateTime.now().millisecondsSinceEpoch > expiresAt - 60000;
    if (isExpired) return _refreshAccessToken(stored.refreshToken);
    return stored.accessToken;
  }

  Future<String?> _refreshAccessToken(String? refreshToken) async {
    if (refreshToken == null) return null;
    try {
      final resp = await Dio().post(
        tokenUrl,
        options: Options(contentType: Headers.formUrlEncodedContentType),
        data: {
          'grant_type': 'refresh_token',
          'refresh_token': refreshToken,
          'client_id': clientId,
          'client_secret': clientSecret,
        },
      );
      final data = resp.data;
      // Spotify rotates refresh_token on refresh; Google doesn't — fall
      // back to the existing one if the provider didn't return a new one.
      final newRefresh = data['refresh_token'] ?? refreshToken;
      await _storeTokens(
          data['access_token'], newRefresh, data['expires_in']);
      return data['access_token'];
    } catch (_) {
      return null;
    }
  }

  Future<void> _storeTokens(
      String accessToken, String? refreshToken, int expiresIn) async {
    await db.saveAuthToken(AuthTokensCompanion.insert(
      service: serviceKey,
      accessToken: Value(accessToken),
      refreshToken: Value(refreshToken),
      expiresAt:
          Value(DateTime.now().millisecondsSinceEpoch + expiresIn * 1000),
    ));
  }
}
