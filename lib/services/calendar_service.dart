import 'package:dio/dio.dart';

import '../database/database.dart';
import 'env_service.dart';
import 'oauth_api_client.dart';

/// Google Calendar REST client. Inherits OAuth plumbing (connect,
/// refresh, disconnect, authed requests) from [OAuthApiClient]; this
/// class just adds the Calendar-specific endpoints.
class CalendarService extends OAuthApiClient {
  static const _port = 8889;
  static const _scopes = 'https://www.googleapis.com/auth/calendar';

  CalendarService(AppDatabase db) : super(db: db);

  @override
  String get serviceKey => 'google';
  @override
  String get logTag => 'Calendar';
  @override
  String get apiBaseUrl => 'https://www.googleapis.com/calendar/v3';
  @override
  String get tokenUrl => 'https://oauth2.googleapis.com/token';
  @override
  String get clientId => Env.get('GOOGLE_CLIENT_ID');
  @override
  String get clientSecret => Env.get('GOOGLE_CLIENT_SECRET');
  @override
  int get redirectPort => _port;
  @override
  String get authorizationUrl =>
      'https://accounts.google.com/o/oauth2/v2/auth'
      '?response_type=code'
      '&client_id=${Uri.encodeComponent(clientId)}'
      '&redirect_uri=${Uri.encodeComponent(redirectUri)}'
      '&scope=${Uri.encodeComponent(_scopes)}'
      '&access_type=offline'
      '&prompt=consent';

  Future<List<dynamic>> getEvents({DateTime? timeMin, DateTime? timeMax}) async {
    final min = (timeMin ?? DateTime.now()).toUtc().toIso8601String();
    final max = (timeMax ?? DateTime.now().add(const Duration(days: 7)))
        .toUtc()
        .toIso8601String();

    try {
      final resp = await authedRequest(
        '/calendars/primary/events',
        queryParameters: {
          'timeMin': min,
          'timeMax': max,
          'singleEvents': true,
          'orderBy': 'startTime',
          'maxResults': 2500,
        },
      );
      final events = List<dynamic>.from(resp.data['items'] ?? []);

      // Holidays are hardcoded in calendar_card.dart (_extraHolidays +
      // _floatingHolidaysFor). We no longer fetch the US holidays calendar.

      events.sort((a, b) {
        final aStart = a['start']?['dateTime'] ?? a['start']?['date'] ?? '';
        final bStart = b['start']?['dateTime'] ?? b['start']?['date'] ?? '';
        return aStart.toString().compareTo(bStart.toString());
      });
      return events;
    } catch (_) {
      return [];
    }
  }

  Future<void> createEvent({
    required String summary,
    String? description,
    required String start,
    required String end,
    bool allDay = false,
  }) async {
    try {
      await authedRequest(
        '/calendars/primary/events',
        method: 'POST',
        data: {
          'summary': summary,
          if (description != null) 'description': description,
          'start': allDay ? {'date': start} : {'dateTime': start},
          'end': allDay ? {'date': end} : {'dateTime': end},
        },
      );
    } on DioException catch (_) {
      // Swallow — the UI doesn't currently surface create failures.
    } catch (_) {
      // Not connected: authedRequest throws before the HTTP call.
    }
  }

  Future<void> deleteEvent(String eventId) async {
    try {
      await authedRequest(
        '/calendars/primary/events/$eventId',
        method: 'DELETE',
      );
    } catch (_) {
      // Swallow — same reasoning as createEvent.
    }
  }
}
