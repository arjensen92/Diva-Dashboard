import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../screens/dashboard_screen.dart';
import 'win95.dart';

class Win95Taskbar extends ConsumerStatefulWidget {
  const Win95Taskbar({super.key});

  @override
  ConsumerState<Win95Taskbar> createState() => _Win95TaskbarState();
}

class _Win95TaskbarState extends ConsumerState<Win95Taskbar> {
  late Timer _timer;
  String _time = '';

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _updateTime());
  }

  void _updateTime() {
    setState(() => _time = DateFormat.jm().format(DateTime.now()));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final menuOpen = ref.watch(startMenuOpenProvider);

    return Container(
      height: 36,
      decoration: const BoxDecoration(
        color: Win95.gray,
        border: Border(top: BorderSide(color: Win95.white, width: 2)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 2),
          Win95Button(
            pressed: menuOpen,
            onTap: () =>
                ref.read(startMenuOpenProvider.notifier).state = !menuOpen,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/icons/windows.png', width: 20, height: 20),
                const SizedBox(width: 4),
                const Text('Start',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.black,
                        height: 1)),
              ],
            ),
          ),
          const SizedBox(width: 4),
          _divider(),
          const SizedBox(width: 4),
          const _Win95WindowButton(
              label: 'Diva-Dashboard.exe', isActive: true),
          const Spacer(),
          _divider(),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              border: Win95.sunkenBorder(width: 1),
            ),
            child: Text(_time,
                style: const TextStyle(
                    fontSize: 12, color: Colors.black, height: 1)),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _divider() {
    return Container(
      width: 2,
      height: 28,
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: Win95.darkGray, width: 1),
          right: BorderSide(color: Win95.white, width: 1),
        ),
      ),
    );
  }
}

class Win95StartMenu extends StatelessWidget {
  final VoidCallback? onStickerPanel;
  final VoidCallback? onChangeBackground;
  final VoidCallback? onShuffle;
  final VoidCallback? onToggleGrid;
  final VoidCallback? onSettings;
  final VoidCallback? onExit;
  final bool isGridMode;

  const Win95StartMenu({
    super.key,
    this.onStickerPanel,
    this.onChangeBackground,
    this.onShuffle,
    this.onToggleGrid,
    this.onSettings,
    this.onExit,
    this.isGridMode = false,
  });

  @override
  Widget build(BuildContext context) {
    return Win95Panel(
      child: SizedBox(
        width: 220,
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(
                width: 28,
                decoration: const BoxDecoration(
                  gradient: Win95.titleGradientVertical,
                ),
                child: const RotatedBox(
                  quarterTurns: 3,
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('Diva Dashboard  95',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1)),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _menuItem(
                        Icons.dashboard_customize, 'Stickers', onStickerPanel),
                    _menuDivider(),
                    _menuItem(Icons.wallpaper, 'Change Background',
                        onChangeBackground),
                    _menuDivider(),
                    _menuItem(Icons.shuffle, 'Shuffle Theme', onShuffle),
                    _menuDivider(),
                    _menuItem(
                        isGridMode ? Icons.view_carousel : Icons.grid_view,
                        isGridMode ? 'Carousel View' : 'Grid View',
                        onToggleGrid),
                    _menuDivider(),
                    _menuItem(Icons.tune, 'Settings', onSettings),
                    _menuDivider(),
                    _menuItem(Icons.close, 'Exit', onExit),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuItem(IconData icon, String label, VoidCallback? onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Colors.black87),
            const SizedBox(width: 12),
            Text(label,
                style: const TextStyle(fontSize: 13, color: Colors.black87)),
          ],
        ),
      ),
    );
  }

  Widget _menuDivider() {
    return Container(
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Win95.darkGray, width: 1),
          bottom: BorderSide(color: Win95.white, width: 1),
        ),
      ),
    );
  }
}

/// Taskbar window tab — active windows use a softer "pressed-ish" bevel
/// (darkGray instead of veryDark) that reads as active rather than held.
class _Win95WindowButton extends StatelessWidget {
  final String label;
  final bool isActive;
  const _Win95WindowButton({required this.label, this.isActive = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Win95.gray,
        border: Win95.windowTabBorder(active: isActive),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Image.asset('assets/icons/dd_icon.apng', width: 28, height: 28),
        const SizedBox(width: 2),
        Flexible(
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        isActive ? FontWeight.w700 : FontWeight.w400,
                    color: Colors.black,
                    height: 1),
                overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}
