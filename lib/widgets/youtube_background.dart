import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';

/// Fullscreen YouTube video player used as a background
/// Runs a tiny local HTTP server to serve the embed page (YouTube blocks file:// embeds)
class YouTubeBackgroundPlayer extends StatefulWidget {
  final String videoId;
  final int startSeconds;
  final double videoAspectRatio;

  const YouTubeBackgroundPlayer({
    super.key,
    required this.videoId,
    required this.startSeconds,
    this.videoAspectRatio = 16 / 9,
  });

  @override
  State<YouTubeBackgroundPlayer> createState() => _YouTubeBackgroundPlayerState();
}

class _YouTubeBackgroundPlayerState extends State<YouTubeBackgroundPlayer> {
  WebviewController? _controller;
  HttpServer? _server;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  String _buildHtml() {
    return '''
<!DOCTYPE html>
<html>
<head>
<style>
  * { margin: 0; padding: 0; overflow: hidden; background: #000; }
  #player, iframe {
    position: fixed !important;
    top: 50% !important; left: 50% !important;
    transform: translate(-50%, -50%) !important;
    border: none !important;
  }
</style>
<script>
  var VIDEO_RATIO = ${widget.videoAspectRatio};
  function sizePlayer() {
    var sw = window.innerWidth, sh = window.innerHeight;
    var screenRatio = sw / sh;
    var w, h;
    // "cover" logic — fill the screen, crop the excess
    if (screenRatio > VIDEO_RATIO) {
      w = sw; h = sw / VIDEO_RATIO;
    } else {
      h = sh; w = sh * VIDEO_RATIO;
    }
    var els = document.querySelectorAll('#player, iframe');
    els.forEach(function(el) { el.style.width = Math.ceil(w) + 'px'; el.style.height = Math.ceil(h) + 'px'; });
  }
  window.addEventListener('resize', sizePlayer);
  setTimeout(sizePlayer, 100);
  setTimeout(sizePlayer, 1000);
  setTimeout(sizePlayer, 3000);
</script>
<style>
</style>
</head>
<body>
<div id="player"></div>
<script>
  var tag = document.createElement('script');
  tag.src = "https://www.youtube.com/iframe_api";
  document.head.appendChild(tag);

  function onYouTubeIframeAPIReady() {
    new YT.Player('player', {
      videoId: '${widget.videoId}',
      playerVars: {
        autoplay: 1, mute: 1, controls: 0, showinfo: 0, rel: 0,
        loop: 1, playlist: '${widget.videoId}', start: ${widget.startSeconds},
        modestbranding: 1, iv_load_policy: 3, disablekb: 1, fs: 0, playsinline: 1
      },
      events: {
        onReady: function(e) { e.target.mute(); e.target.playVideo(); },
        onStateChange: function(e) { if (e.data == 0 || e.data == 2) e.target.playVideo(); }
      }
    });
  }
</script>
</body>
</html>
''';
  }

  Future<void> _init() async {
    try {
      // Start a tiny local HTTP server to serve the embed page
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = _server!.port;
      print('[YouTubeBG] Local server on port $port');

      _server!.listen((request) {
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.html
          ..write(_buildHtml());
        request.response.close();
      });

      // Load the page via http://
      final controller = WebviewController();
      await controller.initialize();
      await controller.setBackgroundColor(Colors.black);
      await controller.loadUrl('http://127.0.0.1:$port');

      print('[YouTubeBG] Loading ${widget.videoId} at ${widget.startSeconds}s');

      if (mounted) {
        setState(() {
          _controller = controller;
          _ready = true;
        });
      }
    } catch (e) {
      print('[YouTubeBG] Failed: $e');
    }
  }

  @override
  void didUpdateWidget(YouTubeBackgroundPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoId != widget.videoId || oldWidget.startSeconds != widget.startSeconds) {
      _controller?.dispose();
      _server?.close(force: true);
      setState(() => _ready = false);
      _init();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _server?.close(force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _controller == null) {
      return const ColoredBox(color: Colors.black, child: SizedBox.expand());
    }
    return IgnorePointer(
      child: Webview(_controller!),
    );
  }
}
