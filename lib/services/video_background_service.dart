import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../theme/animated_backgrounds.dart' show YouTubeBackground;
import 'env_service.dart';
import 'path_service.dart';

/// Loads the YouTube background list from `video_backgrounds.json` at the
/// project root. The user only needs to drop in a YouTube URL (and optionally
/// an `aspectRatio` override); the service parses the video ID, fetches the
/// title and duration from the YouTube Data API on first sight, then writes
/// the enriched entry back to the file so subsequent launches don't re-fetch.
class VideoBackgroundService {
  static final List<YouTubeBackground> _videos = [];
  static List<YouTubeBackground> get videos => List.unmodifiable(_videos);

  static String get _jsonPath =>
      p.join(PathService.projectRoot, 'video_backgrounds.json');

  static Future<void> load() async {
    final file = File(_jsonPath);
    if (!await file.exists()) {
      await _writeSeed(file);
    }

    final raw = await file.readAsString();
    final List decoded;
    try {
      decoded = jsonDecode(raw) as List;
    } catch (e) {
      print('[VideoBG] Failed to parse $_jsonPath: $e');
      return;
    }

    final enriched = <Map<String, dynamic>>[];
    var changed = false;

    for (final item in decoded) {
      if (item is! Map) continue;
      final entry = Map<String, dynamic>.from(item);
      final url = entry['url'] as String?;
      if (url == null || url.isEmpty) continue;

      final videoId = _parseVideoId(url);
      if (videoId == null) {
        print('[VideoBG] Could not extract videoId from "$url" — skipping');
        continue;
      }

      final needsFetch = entry['title'] == null || entry['durationSeconds'] == null;
      if (needsFetch) {
        final meta = await _fetchMetadata(videoId);
        if (meta != null) {
          entry['title'] ??= meta['title'];
          entry['durationSeconds'] ??= meta['durationSeconds'];
          changed = true;
        }
      }

      if (entry['aspectRatio'] == null) {
        final aspect = await _fetchAspectRatio(videoId);
        if (aspect != null) {
          entry['aspectRatio'] = aspect;
          changed = true;
        }
      }

      final title = (entry['title'] as String?) ?? videoId;
      final durationSeconds = (entry['durationSeconds'] as num?)?.toInt() ?? 0;
      final aspectRatio = (entry['aspectRatio'] as num?)?.toDouble() ?? 16.0 / 9.0;

      _videos.add(YouTubeBackground(
        videoId: videoId,
        title: title,
        durationSeconds: durationSeconds,
        aspectRatio: aspectRatio,
      ));
      enriched.add(entry);
    }

    if (changed) {
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(enriched));
      print('[VideoBG] Enriched $_jsonPath with fetched metadata');
    }
    print('[VideoBG] Loaded ${_videos.length} video backgrounds');
  }

  static Future<void> _writeSeed(File file) async {
    const seed = [
      {
        'url': 'https://www.youtube.com/watch?v=Z6hjG6MCcZ8',
        'title': 'Zelda: A Link to the Past',
        'durationSeconds': 16156,
        'aspectRatio': 1.15,
      },
      {
        'url': 'https://www.youtube.com/watch?v=9y2FHdcxRZ8',
        'title': 'Super Mario 64 HD',
        'durationSeconds': 18303,
        'aspectRatio': 4.0 / 3.0,
      },
    ];
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(seed));
    print('[VideoBG] Created seed $_jsonPath');
  }

  /// Accepts any of:
  ///   https://www.youtube.com/watch?v=XXXXXXXXXXX
  ///   https://youtu.be/XXXXXXXXXXX
  ///   https://www.youtube.com/embed/XXXXXXXXXXX
  ///   https://www.youtube.com/shorts/XXXXXXXXXXX
  ///   XXXXXXXXXXX  (bare 11-char ID)
  static String? _parseVideoId(String input) {
    final trimmed = input.trim();
    if (RegExp(r'^[0-9A-Za-z_-]{11}$').hasMatch(trimmed)) return trimmed;
    final m = RegExp(r'(?:v=|/embed/|/shorts/|youtu\.be/)([0-9A-Za-z_-]{11})')
        .firstMatch(trimmed);
    return m?.group(1);
  }

  static Future<Map<String, dynamic>?> _fetchMetadata(String videoId) async {
    final key = Env.get('YOUTUBE_API_KEY');
    if (key.isEmpty) {
      print('[VideoBG] YOUTUBE_API_KEY not set — cannot fetch metadata for $videoId');
      return null;
    }
    try {
      final dio = Dio(BaseOptions(baseUrl: 'https://www.googleapis.com/youtube/v3'));
      final resp = await dio.get('/videos', queryParameters: {
        'part': 'snippet,contentDetails',
        'id': videoId,
        'key': key,
      });
      final items = resp.data['items'] as List?;
      if (items == null || items.isEmpty) {
        print('[VideoBG] No video found for id $videoId');
        return null;
      }
      final snippet = items[0]['snippet'] as Map;
      final details = items[0]['contentDetails'] as Map;
      return {
        'title': snippet['title'] as String,
        'durationSeconds': _parseIso8601Duration(details['duration'] as String),
      };
    } catch (e) {
      print('[VideoBG] Failed to fetch metadata for $videoId: $e');
      return null;
    }
  }

  /// Scrapes the YouTube watch page to detect the video's transcoded aspect
  /// ratio. Returns null if the page can't be fetched or no dimensions found.
  /// Note: this reflects what YouTube transcoded the video to (usually 16:9),
  /// not the original content's aspect. Supply an explicit `aspectRatio` in
  /// the JSON to override for content-specific crops.
  static Future<double?> _fetchAspectRatio(String videoId) async {
    try {
      final dio = Dio();
      final resp = await dio.get(
        'https://www.youtube.com/watch?v=$videoId',
        options: Options(
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                'AppleWebKit/537.36 (KHTML, like Gecko) '
                'Chrome/120.0.0.0 Safari/537.36',
            'Accept-Language': 'en-US,en;q=0.9',
          },
          responseType: ResponseType.plain,
        ),
      );
      final html = resp.data as String;
      // Scan all "width":N,"height":N pairs; video stream formats have the
      // largest dimensions (thumbnails and UI elements are smaller).
      int bestW = 0, bestH = 0;
      for (final m in RegExp(r'"width":(\d+),"height":(\d+)').allMatches(html)) {
        final w = int.parse(m.group(1)!);
        final h = int.parse(m.group(2)!);
        if (w > bestW && h > 0) {
          bestW = w;
          bestH = h;
        }
      }
      if (bestW > 0 && bestH > 0) {
        final ratio = bestW / bestH;
        print('[VideoBG] Detected aspect ratio $ratio (${bestW}x$bestH) for $videoId');
        return ratio;
      }
      return null;
    } catch (e) {
      print('[VideoBG] Failed to scrape aspect ratio for $videoId: $e');
      return null;
    }
  }

  /// Parses ISO 8601 durations like "PT4H29M16S" into total seconds.
  static int _parseIso8601Duration(String d) {
    final m = RegExp(r'^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$').firstMatch(d);
    if (m == null) return 0;
    final h = int.parse(m.group(1) ?? '0');
    final min = int.parse(m.group(2) ?? '0');
    final s = int.parse(m.group(3) ?? '0');
    return h * 3600 + min * 60 + s;
  }
}
