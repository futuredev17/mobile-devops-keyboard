import 'dart:async';

import 'package:flutter/material.dart';

const Color kPanelBg = Color(0xFF161B22);
const Color kPanelBorder = Color(0xFF30363D);
const Color kTextDim = Color(0xFF6E7681);
const Color kTextMain = Color(0xFFC9D1D9);
const Color kAccent = Color(0xFF1F6FEB);

/// 面板顶部/侧边的胶囊小按钮。
class MiniChip extends StatelessWidget {
  const MiniChip({
    super.key,
    required this.label,
    required this.onTap,
    this.active = false,
    this.tint,
    this.fontSize = 10,
  });

  final String label;
  final VoidCallback onTap;
  final bool active;
  final Color? tint;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final Color bg = active ? (tint ?? kAccent) : const Color(0xFF21262D);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: kPanelBorder, width: 0.6),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(
            fontSize: fontSize,
            color: const Color(0xFFDCE3EA),
            fontWeight: FontWeight.w600,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}

/// 一个键帽。长按可连发（退格 / 方向键用得到），手感和物理键盘接近。
class KeyCap extends StatefulWidget {
  const KeyCap({
    super.key,
    required this.label,
    required this.onTap,
    required this.fontSize,
    this.active = false,
    this.repeatable = false,
    this.dim = false,
  });

  final String label;
  final VoidCallback onTap;
  final double fontSize;
  final bool active;
  final bool repeatable;
  final bool dim;

  @override
  State<KeyCap> createState() => _KeyCapState();
}

class _KeyCapState extends State<KeyCap> {
  bool _pressed = false;
  bool _repeating = false;
  Timer? _delay;
  Timer? _interval;

  void _press() {
    setState(() => _pressed = true);
    _repeating = false;
    if (!widget.repeatable) return;
    _delay = Timer(const Duration(milliseconds: 400), () {
      _repeating = true;
      widget.onTap();
      _interval = Timer.periodic(
        const Duration(milliseconds: 55),
        (_) => widget.onTap(),
      );
    });
  }

  void _release({required bool fire}) {
    _delay?.cancel();
    _interval?.cancel();
    _delay = null;
    _interval = null;
    if (mounted) setState(() => _pressed = false);
    if (fire && !_repeating) widget.onTap();
    _repeating = false;
  }

  @override
  void dispose() {
    _delay?.cancel();
    _interval?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color bg;
    if (widget.active) {
      bg = kAccent;
    } else if (_pressed) {
      bg = const Color(0xFF3D4654);
    } else if (widget.dim) {
      bg = const Color(0xFF1B2028);
    } else {
      bg = const Color(0xFF262C36);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _press(),
      onTapUp: (_) => _release(fire: true),
      onTapCancel: () => _release(fire: false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: const Color(0xFF343C48), width: 0.7),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            child: Text(
              widget.label,
              maxLines: 1,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: widget.fontSize,
                height: 1.0,
                color: widget.active ? Colors.white : const Color(0xFFD6DEE8),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
