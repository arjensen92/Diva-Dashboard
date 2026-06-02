import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop_audio_capture/audio_capture.dart';

class VisualizerState {
  final List<int> fft;
  final List<int> waveform;
  final bool active;
  const VisualizerState({this.fft = const [], this.waveform = const [], this.active = false});
}

class VisualizerNotifier extends StateNotifier<VisualizerState> {
  final SystemAudioCapture _capture = SystemAudioCapture();
  StreamSubscription<Uint8List>? _audioSub;
  Timer? _updateTimer;
  Uint8List? _latestData;

  VisualizerNotifier() : super(const VisualizerState()) {
    // Delay startup so it doesn't block app launch
    Future.delayed(const Duration(seconds: 5), _start);
  }

  Future<void> restart() async {
    _audioSub?.cancel();
    _updateTimer?.cancel();
    try { await _capture.stopCapture(); } catch (_) {}
    state = const VisualizerState();
    await Future.delayed(const Duration(milliseconds: 500));
    await _start();
  }

  Future<void> _start() async {
    try {
      await _capture.startCapture().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          print('[Visualizer] Audio capture timed out');
        },
      );
      state = VisualizerState(fft: state.fft, waveform: state.waveform, active: true);
      _audioSub = _capture.audioStream?.listen((data) => _latestData = data);
      _updateTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (_latestData != null) {
          _process(_latestData!);
          _latestData = null;
        }
      });
    } catch (e) {
      print('[Visualizer] Failed to start: $e');
    }
  }

  void _process(Uint8List data) {
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
    final waveform = List<int>.generate(1024, (i) => ((samples[i] + 32768) * 255 ~/ 65535));

    final bands = 25; // was 32, removed 7 from the right (high frequencies)
    final bandSize = 1024 ~/ 32; // still sample from 32 bands worth of data
    final fft = List<int>.generate(bands, (i) {
      int sum = 0;
      for (int j = 0; j < bandSize; j++) sum += (waveform[i * bandSize + j] - 128).abs();
      // Amplify — boost the signal 5x and clamp to 0-255 for dramatic bars
      int val = (sum ~/ bandSize) * 5;
      return val.clamp(0, 255);
    });

    state = VisualizerState(fft: fft, waveform: waveform, active: true);
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _audioSub?.cancel();
    _capture.stopCapture();
    super.dispose();
  }
}

final visualizerProvider = StateNotifierProvider<VisualizerNotifier, VisualizerState>((ref) {
  return VisualizerNotifier();
});

/// Compact bar visualizer widget with scrolling rainbow
class MiniVisualizer extends ConsumerStatefulWidget {
  final double height;

  const MiniVisualizer({super.key, this.height = 60});

  @override
  ConsumerState<MiniVisualizer> createState() => _MiniVisualizerState();
}

class _MiniVisualizerState extends ConsumerState<MiniVisualizer> with SingleTickerProviderStateMixin {
  late AnimationController _colorController;

  @override
  void initState() {
    super.initState();
    _colorController = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
  }

  @override
  void dispose() {
    _colorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(visualizerProvider);
    if (state.fft.isEmpty) return SizedBox(height: widget.height);
    return AnimatedBuilder(
      animation: _colorController,
      builder: (_, __) => SizedBox(
        height: widget.height,
        width: double.infinity,
        child: CustomPaint(
          painter: _BarPainter(
            data: state.fft,
            color: Colors.white,
            rainbow: true,
            colorOffset: _colorController.value * 360,
          ),
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  final List<int> data;
  final Color color;
  final bool rainbow;
  final double colorOffset;
  _BarPainter({required this.data, required this.color, this.rainbow = false, this.colorOffset = 0});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty || size.isEmpty) return;
    final barWidth = size.width / data.length;
    for (int i = 0; i < data.length; i++) {
      final ratio = data[i] / 255.0;
      final barHeight = ratio * size.height;
      final barColor = rainbow
          ? HSLColor.fromAHSL(1.0, ((i / data.length) * 360 + colorOffset) % 360, 0.9, 0.55).toColor()
          : color;
      final paint = Paint()..color = barColor..style = PaintingStyle.fill;
      canvas.drawRect(Rect.fromLTWH(i * barWidth, size.height - barHeight, barWidth - 1, barHeight), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) => true;
}
