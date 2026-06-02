import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/dashboard_screen.dart' show stickerTabProvider;
import '../services/gachamon_game_service.dart';
import 'win95.dart';

/// Two Win95-styled tabs for the sticker drawer — Graphics and Gachamon.
/// Renders its own custom bevel (raised on the active tab, with no bottom
/// edge so it merges into the content below; thinner flat border on the
/// inactive tab). Not built from the standard Win95 primitives because
/// the "active tab has no bottom" detail doesn't fit them.
class StickerTabs extends StatelessWidget {
  final WidgetRef ref;
  const StickerTabs({super.key, required this.ref});

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(gachamonGameProvider);
    final active = ref.watch(stickerTabProvider);
    final gachamonCount = game.catchOrder.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      color: Win95.gray,
      child: Row(
        children: [
          _tab(context, label: 'Graphics', tab: 'graphics', active: active),
          const SizedBox(width: 4),
          _tab(
            context,
            label: gachamonCount > 0 ? 'Gachamon ($gachamonCount)' : 'Gachamon',
            tab: 'gachamon',
            active: active,
          ),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context,
      {required String label, required String tab, required String active}) {
    final isActive = tab == active;
    return GestureDetector(
      onTap: () => ref.read(stickerTabProvider.notifier).state = tab,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Win95.gray,
          border: Border(
            top: BorderSide(
              color: isActive ? Win95.white : Win95.darkGray,
              width: isActive ? 2 : 1,
            ),
            left: BorderSide(
              color: isActive ? Win95.white : Win95.darkGray,
              width: isActive ? 2 : 1,
            ),
            right: BorderSide(
              color: isActive ? Win95.veryDark : Win95.darkGray,
              width: isActive ? 2 : 1,
            ),
            // Active tab has no bottom border so it visually merges with content below.
            bottom: BorderSide(
              color: Win95.gray,
              width: isActive ? 0 : 1,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}

/// Wraps a sticker with a gentle sine-based vertical bob. Each instance
/// gets a deterministic phase offset from [phaseSeed] (hashed into the
/// [0, 2π) range) so a grid of stickers doesn't bob in lockstep.
class BobbingSticker extends StatefulWidget {
  final Widget child;
  final int phaseSeed;
  const BobbingSticker({super.key, required this.child, this.phaseSeed = 0});

  @override
  State<BobbingSticker> createState() => _BobbingStickerState();
}

class _BobbingStickerState extends State<BobbingSticker>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late double _phase;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _phase = (widget.phaseSeed.abs() % 1000) / 1000.0 * 2 * math.pi;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final t = _c.value * 2 * math.pi + _phase;
        return Transform.translate(
          offset: Offset(0, math.sin(t) * 3.0),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Sticker gesture wrapper: single-pointer drag, plus two-pointer pinch
/// (rotate + scale). The callbacks receive incremental deltas — the
/// parent is responsible for applying them to the sticker's stored
/// transform.
class DraggableSticker extends StatefulWidget {
  final Widget child;
  final void Function(double dx, double dy) onDrag;
  final void Function(double deltaRadians)? onRotate;
  final void Function(double scaleChange)? onResize;
  const DraggableSticker({
    super.key,
    required this.child,
    required this.onDrag,
    this.onRotate,
    this.onResize,
  });
  @override
  State<DraggableSticker> createState() => _DraggableStickerState();
}

class _DraggableStickerState extends State<DraggableSticker> {
  final Map<int, Offset> _pointers = {};
  double? _lastAngle;
  double? _lastDistance;

  double _angleBetweenPointers() {
    final pts = _pointers.values.toList();
    if (pts.length < 2) return 0;
    return (pts[1] - pts[0]).direction;
  }

  double _distanceBetweenPointers() {
    final pts = _pointers.values.toList();
    if (pts.length < 2) return 0;
    return (pts[1] - pts[0]).distance;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        _pointers[event.pointer] = event.position;
        if (_pointers.length == 2) {
          _lastAngle = _angleBetweenPointers();
          _lastDistance = _distanceBetweenPointers();
        }
      },
      onPointerMove: (event) {
        _pointers[event.pointer] = event.position;
        if (_pointers.length == 1) {
          widget.onDrag(event.delta.dx, event.delta.dy);
        } else if (_pointers.length >= 2) {
          if (widget.onRotate != null) {
            final newAngle = _angleBetweenPointers();
            if (_lastAngle != null) widget.onRotate!(newAngle - _lastAngle!);
            _lastAngle = newAngle;
          }
          if (widget.onResize != null) {
            final newDist = _distanceBetweenPointers();
            if (_lastDistance != null && _lastDistance! > 0) {
              widget.onResize!(newDist / _lastDistance!);
            }
            _lastDistance = newDist;
          }
        }
      },
      onPointerUp: (event) {
        _pointers.remove(event.pointer);
        _lastAngle = null;
        _lastDistance = null;
      },
      onPointerCancel: (event) {
        _pointers.remove(event.pointer);
        _lastAngle = null;
        _lastDistance = null;
      },
      child: widget.child,
    );
  }
}
