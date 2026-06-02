import 'dart:async';
import 'dart:io';

/// Shared OAuth loopback server pattern for desktop apps.
class OAuthLoopback {
  static Future<String?> getAuthCode({
    required String authUrl,
    int port = 0,
  }) async {
    final completer = Completer<String?>();
    HttpServer? server;

    try {
      // Step 1: Bind local server
      print('[OAuth] Binding to 127.0.0.1:$port ...');
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      final actualPort = server.port;
      print('[OAuth] Server listening on port $actualPort');

      final finalUrl = authUrl.replaceAll('{PORT}', actualPort.toString());

      // Step 2: Open browser using Windows 'start' command
      print('[OAuth] Opening browser...');
      // Write URL to a temp HTML file to avoid URL escaping issues with cmd start
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}\\oauth_redirect.html');
      await tempFile.writeAsString('<html><head><meta http-equiv="refresh" content="0;url=$finalUrl"></head><body>Redirecting...</body></html>');

      final result = await Process.run(
        'cmd',
        ['/c', 'start', '', tempFile.path],
        runInShell: false,
      );
      print('[OAuth] Browser launch exit code: ${result.exitCode}');
      if (result.exitCode != 0) {
        print('[OAuth] stderr: ${result.stderr}');
        // Fallback: try rundll32
        await Process.run('rundll32', ['url.dll,FileProtocolHandler', finalUrl]);
      }

      // Step 3: Listen for callback
      print('[OAuth] Waiting for callback...');
      server.listen((request) async {
        print('[OAuth] Got request: ${request.uri.path}');
        if (request.uri.path == '/callback') {
          final code = request.uri.queryParameters['code'];
          final error = request.uri.queryParameters['error'];

          if (error != null) {
            print('[OAuth] Error from provider: $error');
            request.response
              ..statusCode = 200
              ..headers.contentType = ContentType.html
              ..write(_resultPage('Authorization Failed', error, false));
            await request.response.close();
            if (!completer.isCompleted) completer.complete(null);
          } else if (code != null) {
            print('[OAuth] Got authorization code');
            request.response
              ..statusCode = 200
              ..headers.contentType = ContentType.html
              ..write(_resultPage('Connected!', 'You can close this tab and return to the dashboard.', true));
            await request.response.close();
            if (!completer.isCompleted) completer.complete(code);
          }
        }
      });

      // Timeout after 5 minutes
      return await completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          print('[OAuth] Timed out waiting for callback');
          return null;
        },
      );
    } catch (e, stack) {
      print('[OAuth] ERROR: $e');
      print('[OAuth] Stack: $stack');
      return null;
    } finally {
      await server?.close(force: true);
      print('[OAuth] Server closed');
    }
  }

  static String _resultPage(String title, String message, bool success) {
    final color = success ? '#22c55e' : '#ef4444';
    return '''<html><body style="background:#0f1117;color:#e4e6ef;font-family:Segoe UI,sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0">
<div style="text-align:center">
<h2 style="color:$color;font-size:28px">$title</h2>
<p style="color:#8b8fa3;font-size:16px">$message</p>
</div></body></html>''';
  }
}
