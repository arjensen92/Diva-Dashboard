import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:desktop_audio_capture/audio_capture.dart';
import 'package:audio_visualizer/audio_visualizer.dart';
import 'package:audio_visualizer/visualizers/visualizers.dart';
import '../widgets/full_screen_overlay.dart';

const _spotifyGreen = Color(0xFF1DB954);
const _spotifyBlack = Color(0xFF121212);

class VisualizerScreen extends StatefulWidget {
  const VisualizerScreen({super.key});

  @override
  State<VisualizerScreen> createState() => _VisualizerScreenState();
}

class _VisualizerScreenState extends State<VisualizerScreen> {
  final SystemAudioCapture _capture = SystemAudioCapture();
  StreamSubscription<Uint8List>? _audioSub;
  bool _active = false;
  String? _error;

  // Throttled visualizer data
  List<int> _fftData = [];
  List<int> _waveData = [];
  Timer? _updateTimer;

  // Buffer for latest audio data
  Uint8List? _latestData;

  @override
  void initState() {
    super.initState();
    _startCapture();
    // Update UI at 30fps max — prevents layout thrashing
    _updateTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (_latestData != null && mounted) {
        _processAudio(_latestData!);
        _latestData = null;
      }
    });
  }

  void _processAudio(Uint8List data) {
    // Ensure exactly 2048 bytes (1024 int16 samples)
    Uint8List padded;
    if (data.length >= 2048) {
      padded = Uint8List.view(data.buffer, data.offsetInBytes, 2048);
    } else if (data.length >= 2) {
      padded = Uint8List(2048);
      padded.setRange(0, data.length, data);
    } else {
      return;
    }

    final byteData = padded.buffer.asByteData(padded.offsetInBytes, padded.lengthInBytes);
    final samples = Int16List.view(byteData.buffer, byteData.offsetInBytes, 1024);

    // Convert to 0-255 range for visualization
    final waveform = List<int>.generate(1024, (i) => ((samples[i] + 32768) * 255 ~/ 65535));

    // Simple FFT approximation — group into frequency bands
    final bands = 64;
    final bandSize = 1024 ~/ bands;
    final fft = List<int>.generate(bands, (i) {
      int sum = 0;
      for (int j = 0; j < bandSize; j++) {
        sum += waveform[i * bandSize + j].abs();
      }
      return (sum ~/ bandSize);
    });

    if (mounted) {
      setState(() {
        _fftData = fft;
        _waveData = waveform;
      });
    }
  }

  Future<void> _startCapture() async {
    try {
      await _capture.startCapture();
      setState(() => _active = true);
      _audioSub = _capture.audioStream?.listen(
        (data) => _latestData = data, // Just buffer, don't process immediately
        onError: (e) => setState(() => _error = e.toString()),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _audioSub?.cancel();
    _capture.stopCapture();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FullScreenOverlay(
      title: 'Visualizer',
      child: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Error: $_error', style: const TextStyle(color: Colors.red)),
            ),

          // Bar visualizer
          SizedBox(
            height: 300,
            width: double.infinity,
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _spotifyBlack,
                borderRadius: BorderRadius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: _fftData.isEmpty
                  ? const Center(child: Text('Waiting for audio...', style: TextStyle(color: Colors.white38)))
                  : CustomPaint(
                      size: Size.infinite,
                      painter: _BarPainter(data: _fftData, color: _spotifyGreen),
                    ),
            ),
          ),

          // Waveform
          SizedBox(
            height: 200,
            width: double.infinity,
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _spotifyBlack,
                borderRadius: BorderRadius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: _waveData.isEmpty
                  ? const SizedBox.shrink()
                  : CustomPaint(
                      size: Size.infinite,
                      painter: _WavePainter(data: _waveData, color: _spotifyGreen),
                    ),
            ),
          ),

          // Status
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_active ? Icons.graphic_eq : Icons.mic_off, color: _active ? _spotifyGreen : Colors.white38),
                const SizedBox(width: 8),
                Text(
                  _active ? 'Listening to system audio' : 'Not active',
                  style: TextStyle(color: _active ? _spotifyGreen : Colors.white38),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Simple bar visualizer painter
class _BarPainter extends CustomPainter {
  final List<int> data;
  final Color color;
  _BarPainter({required this.data, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty || size.isEmpty) return;
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final barWidth = size.width / data.length;
    for (int i = 0; i < data.length; i++) {
      final ratio = data[i] / 255.0;
      final barHeight = ratio * size.height;
      canvas.drawRect(
        Rect.fromLTWH(i * barWidth, size.height - barHeight, barWidth - 1, barHeight),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) => true;
}

/// Simple waveform painter
class _WavePainter extends CustomPainter {
  final List<int> data;
  final Color color;
  _WavePainter({required this.data, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty || size.isEmpty) return;
    final paint = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1.5;
    final path = Path();
    final step = size.width / data.length;
    for (int i = 0; i < data.length; i++) {
      final x = i * step;
      final y = size.height - (data[i] / 255.0 * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => true;
}
