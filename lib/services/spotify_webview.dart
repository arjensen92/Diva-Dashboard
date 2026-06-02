import 'dart:ui';

import 'package:webview_windows/webview_windows.dart';

/// Helpers for the in-app Spotify web player. Encapsulates the two pieces
/// of "make webview_windows behave like Spotify's web client" — audio
/// blocking (so the WebView doesn't steal playback from the Spotify
/// Connect device) and mouse-wheel scroll forwarding (the embedded
/// browser doesn't get native scroll events because the host Flutter
/// Listener consumes them).
class SpotifyWebView {
  SpotifyWebView._();

  /// Creates a fully-initialized WebView controller pointed at [url] with
  /// the audio-blocker script pre-registered. The caller owns the
  /// controller and is responsible for disposal.
  static Future<WebviewController> createAudioBlocked(
    String url, {
    Color backgroundColor = const Color(0xFF121212),
  }) async {
    final controller = WebviewController();
    await controller.initialize();
    await controller.setBackgroundColor(backgroundColor);
    // Re-run the blocker after every navigation — Spotify's SPA keeps
    // re-creating media elements as the user navigates.
    controller.loadingState.listen((state) {
      if (state == LoadingState.navigationCompleted) {
        controller.executeScript(_audioBlockerScript);
      }
    });
    await controller.loadUrl(url);
    return controller;
  }

  /// Forwards a mouse-wheel scroll at screen position [pos] (relative to
  /// the WebView) by [dy] pixels. Finds the nearest scrollable ancestor
  /// under the pointer rather than blindly scrolling document.body —
  /// matters because Spotify's layout uses an internal scroll container
  /// for the track list rather than the window.
  static void scrollAt(
    WebviewController controller,
    Offset pos,
    double dy,
  ) {
    controller.executeScript('''
      (function() {
        function findScrollable(el) {
          while (el && el !== document.body) {
            var style = getComputedStyle(el);
            if (style.overflowY === 'auto' || style.overflowY === 'scroll') {
              if (el.scrollHeight > el.clientHeight) return el;
            }
            el = el.parentElement;
          }
          return document.scrollingElement || document.documentElement;
        }
        var target = document.elementFromPoint(${pos.dx}, ${pos.dy});
        var scrollable = findScrollable(target);
        scrollable.scrollBy(0, $dy);
      })();
    ''');
  }

  /// Two strategies for cutting off the WebView's audio: (1) a 500 ms
  /// polling loop that mutes and pauses every `<audio>`/`<video>` element,
  /// and (2) replacing `window.AudioContext` with a shim that closes
  /// each new context immediately. The poll handles DOM-level audio
  /// Spotify attaches on user interaction; the shim catches Web Audio
  /// pipelines the Spotify player builds for visualizations. Belt +
  /// suspenders — leaving either one out lets audio bleed through.
  static const _audioBlockerScript = '''
    (function() {
      setInterval(function() {
        document.querySelectorAll('audio, video').forEach(function(el) {
          el.muted = true;
          el.pause();
          el.volume = 0;
        });
      }, 500);
      try {
        var OAC = window.AudioContext || window.webkitAudioContext;
        if (OAC) {
          window.AudioContext = function() {
            var c = new OAC();
            c.close();
            return c;
          };
          if (window.webkitAudioContext) window.webkitAudioContext = window.AudioContext;
        }
      } catch(e) {}
    })();
  ''';
}
