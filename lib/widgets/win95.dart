/// Central Win95 theme primitives. All Win95-styled UI in the app should
/// compose these colors, borders, and widgets rather than re-defining them.
library;

import 'package:flutter/material.dart';

/// Win95 palette + border/gradient factories.
class Win95 {
  Win95._();

  static const gray = Color(0xFFC0C0C0);
  static const darkGray = Color(0xFF808080);
  static const veryDark = Color(0xFF404040);
  static const white = Color(0xFFFFFFFF);
  static const titleBlueLeft = Color(0xFF000080);
  static const titleBlueRight = Color(0xFF1084D0);

  /// Classic blue-to-lighter-blue title bar gradient.
  static const titleGradient = LinearGradient(
    colors: [titleBlueLeft, titleBlueRight],
  );

  /// Vertical variant used by the Start menu side rail.
  static const titleGradientVertical = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [titleBlueLeft, titleBlueRight],
  );

  /// Drop shadow applied to white title-bar text.
  static const titleTextShadows = [
    Shadow(color: Color(0x66000000), blurRadius: 0, offset: Offset(1, 1)),
  ];

  /// Raised bevel (white top/left, veryDark bottom/right). Use on windows
  /// and unpressed buttons that appear to pop out of the surface.
  static Border raisedBorder({double width = 2}) => Border(
        top: BorderSide(color: white, width: width),
        left: BorderSide(color: white, width: width),
        right: BorderSide(color: veryDark, width: width),
        bottom: BorderSide(color: veryDark, width: width),
      );

  /// Sunken bevel (darkGray top/left, white bottom/right). Use on inset
  /// content areas like text fields and the inner region of a window.
  static Border sunkenBorder({double width = 1.5}) => Border(
        top: BorderSide(color: darkGray, width: width),
        left: BorderSide(color: darkGray, width: width),
        right: BorderSide(color: white, width: width),
        bottom: BorderSide(color: white, width: width),
      );

  /// Button border that flips raised ↔ sunken based on [pressed].
  static Border pressableBorder({required bool pressed, double width = 2}) =>
      Border(
        top: BorderSide(color: pressed ? veryDark : white, width: width),
        left: BorderSide(color: pressed ? veryDark : white, width: width),
        right: BorderSide(color: pressed ? white : veryDark, width: width),
        bottom: BorderSide(color: pressed ? white : veryDark, width: width),
      );

  /// Taskbar window-button border: uses the softer [darkGray] on the
  /// pressed sides instead of [veryDark], giving a less-sunken look for
  /// active windows in the taskbar.
  static Border windowTabBorder({required bool active, double width = 2}) =>
      Border(
        top: BorderSide(color: active ? darkGray : white, width: width),
        left: BorderSide(color: active ? darkGray : white, width: width),
        right: BorderSide(color: active ? white : veryDark, width: width),
        bottom: BorderSide(color: active ? white : veryDark, width: width),
      );
}

/// Classic Win95 title bar: blue gradient strip with optional [leading]
/// icon, [title] text, and any combination of min/max/close buttons.
/// Pass a callback for any button you want visible; omit to hide it.
class Win95TitleBar extends StatelessWidget {
  final String title;
  final Widget? leading;
  final double? titleFontSize;
  final double? height;
  final EdgeInsets padding;
  final VoidCallback? onClose;
  final VoidCallback? onMinimize;
  final VoidCallback? onMaximize;

  /// Extra widgets rendered between the title text and the min/max/close
  /// row — used for screen-specific controls like a Cast button.
  final List<Widget> trailing;

  /// Edge length of each title button (auto-scales its font).
  final double buttonSize;

  const Win95TitleBar({
    super.key,
    required this.title,
    this.leading,
    this.titleFontSize,
    this.height,
    this.padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    this.onClose,
    this.onMinimize,
    this.onMaximize,
    this.trailing = const [],
    this.buttonSize = 18,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: padding,
      decoration: const BoxDecoration(gradient: Win95.titleGradient),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: Colors.white,
                fontSize: titleFontSize ?? (buttonSize <= 22 ? 13 : 16),
                fontWeight: FontWeight.w700,
                shadows: Win95.titleTextShadows,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ...trailing,
          if (trailing.isNotEmpty) const SizedBox(width: 4),
          if (onMinimize != null) ...[
            Win95TitleButton(label: '_', size: buttonSize, onTap: onMinimize),
            const SizedBox(width: 2),
          ],
          if (onMaximize != null) ...[
            Win95TitleButton(label: '□', size: buttonSize, onTap: onMaximize),
            const SizedBox(width: 2),
          ],
          if (onClose != null)
            Win95TitleButton(label: '×', size: buttonSize, onTap: onClose),
        ],
      ),
    );
  }
}

/// Small square beveled button used in title bars (min / max / close).
/// Border thickness and font size scale with [size].
class Win95TitleButton extends StatelessWidget {
  final String label;
  final double size;
  final VoidCallback? onTap;

  const Win95TitleButton({
    super.key,
    required this.label,
    this.size = 18,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderWidth = size <= 22 ? 1.0 : 2.0;
    // × renders larger than _/□ because the glyph's visual weight is smaller.
    final fontSize = label == '×' ? size * 0.65 : size * 0.52;
    final btn = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Win95.gray,
        border: Win95.raisedBorder(width: borderWidth),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            color: Colors.black,
            height: 1,
          ),
        ),
      ),
    );
    return onTap == null ? btn : GestureDetector(onTap: onTap, child: btn);
  }
}

/// Win95 panel: gray fill + raised bevel. [fillOpacity] fades only the
/// fill color, leaving the border fully opaque.
class Win95Panel extends StatelessWidget {
  final Widget child;
  final double fillOpacity;
  final double borderWidth;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  const Win95Panel({
    super.key,
    required this.child,
    this.fillOpacity = 1.0,
    this.borderWidth = 2,
    this.padding,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      margin: margin,
      decoration: BoxDecoration(
        color: fillOpacity >= 1.0
            ? Win95.gray
            : Win95.gray.withValues(alpha: fillOpacity),
        border: Win95.raisedBorder(width: borderWidth),
      ),
      child: child,
    );
  }
}

/// Win95 sunken inset panel — used for the inner content area of a window
/// and for anything that should look "pushed in" like text fields.
class Win95InsetPanel extends StatelessWidget {
  final Widget child;
  final Color? fillColor;
  final double fillOpacity;
  final double borderWidth;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  const Win95InsetPanel({
    super.key,
    required this.child,
    this.fillColor,
    this.fillOpacity = 1.0,
    this.borderWidth = 1.5,
    this.padding,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final base = fillColor ?? Colors.white;
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: fillOpacity >= 1.0 ? base : base.withValues(alpha: fillOpacity),
        border: Win95.sunkenBorder(width: borderWidth),
      ),
      child: child,
    );
  }
}

/// Pressable Win95 button. Inverts its bevel when [pressed] is true.
class Win95Button extends StatelessWidget {
  final Widget child;
  final bool pressed;
  final VoidCallback? onTap;
  final double? height;
  final double borderWidth;
  final EdgeInsets padding;

  const Win95Button({
    super.key,
    required this.child,
    this.pressed = false,
    this.onTap,
    this.height = 28,
    this.borderWidth = 2,
    this.padding = const EdgeInsets.symmetric(horizontal: 8),
  });

  @override
  Widget build(BuildContext context) {
    final btn = Container(
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: Win95.gray,
        border: Win95.pressableBorder(pressed: pressed, width: borderWidth),
      ),
      child: Center(child: child),
    );
    return onTap == null ? btn : GestureDetector(onTap: onTap, child: btn);
  }
}
