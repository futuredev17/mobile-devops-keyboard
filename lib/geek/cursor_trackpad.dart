import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'geek_editing_engine.dart';
import 'ui_bits.dart';

/// 键盘右侧的光标触摸区（小触摸板）。
///
/// 手指横向拖动 = 逐字符移动光标，纵向拖动 = 跨行移动。
/// 开启「选择」模式后拖动就是扩选，等价于按住 Shift + 方向键。
class CursorTrackpad extends StatefulWidget {
  const CursorTrackpad({
    super.key,
    required this.engine,
    required this.caretVisible,
    required this.onToggleCaret,
  });

  final GeekEditingEngine engine;
  final bool caretVisible;
  final VoidCallback onToggleCaret;

  @override
  State<CursorTrackpad> createState() => _CursorTrackpadState();
}

class _CursorTrackpadState extends State<CursorTrackpad> {
  static const double _stepX = 4.5;
  static const double _stepY = 18;

  double _accX = 0;
  double _accY = 0;
  int _ticks = 0;
  bool _selectMode = false;
  bool _dragging = false;

  void _onStart(DragStartDetails details) {
    _accX = 0;
    _accY = 0;
    setState(() => _dragging = true);
  }

  void _onEnd(DragEndDetails details) {
    setState(() => _dragging = false);
  }

  void _onUpdate(DragUpdateDetails details) {
    final GeekEditingEngine e = widget.engine;
    _accX += details.delta.dx;
    _accY += details.delta.dy;

    bool moved = false;
    while (_accX >= _stepX) {
      e.moveRight(extend: _selectMode);
      _accX -= _stepX;
      moved = true;
    }
    while (_accX <= -_stepX) {
      e.moveLeft(extend: _selectMode);
      _accX += _stepX;
      moved = true;
    }
    while (_accY >= _stepY) {
      e.moveDown(extend: _selectMode);
      _accY -= _stepY;
      moved = true;
    }
    while (_accY <= -_stepY) {
      e.moveUp(extend: _selectMode);
      _accY += _stepY;
      moved = true;
    }

    if (!moved) return;
    _ticks++;
    if (_ticks % 5 == 0) HapticFeedback.selectionClick();
    setState(() {}); // 刷新 Ln/Col 读数
  }

  String get _posLabel {
    final TextEditingValue v = widget.engine.value;
    final int raw = v.selection.isValid ? v.selection.extentOffset : v.text.length;
    final int offset = raw < 0 ? 0 : (raw > v.text.length ? v.text.length : raw);
    final String before = v.text.substring(0, offset);
    final int line = '\n'.allMatches(before).length + 1;
    final int lastNl = before.lastIndexOf('\n');
    final int col = offset - (lastNl + 1) + 1;
    final String sel = v.selection.isValid && !v.selection.isCollapsed
        ? '  sel ${v.selection.start}:${v.selection.end}'
        : '';
    return 'Ln $line, Col $col$sel';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0B0F14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kPanelBorder, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 3),
            child: Wrap(
              spacing: 5,
              runSpacing: 4,
              children: <Widget>[
                MiniChip(
                  label: widget.caretVisible ? '光标 ●' : '光标 ○',
                  onTap: widget.onToggleCaret,
                  active: widget.caretVisible,
                ),
                MiniChip(
                  label: '选择',
                  onTap: () => setState(() => _selectMode = !_selectMode),
                  active: _selectMode,
                  tint: const Color(0xFF8957E5),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: Text(
              _posLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 9.5,
                color: kTextDim,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: _onStart,
                onPanUpdate: _onUpdate,
                onPanEnd: _onEnd,
                onPanCancel: () => setState(() => _dragging = false),
                onDoubleTap: () => setState(() => _selectMode = !_selectMode),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    gradient: RadialGradient(
                      colors: _dragging
                          ? const <Color>[Color(0xFF23303F), Color(0xFF0B0F14)]
                          : const <Color>[Color(0xFF151C25), Color(0xFF0B0F14)],
                      radius: 1.0,
                    ),
                    border: Border.all(
                      color: _selectMode
                          ? const Color(0xFF8957E5)
                          : const Color(0xFF232B36),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _selectMode
                        ? '⇧ 选择模式\n拖动扩展选区'
                        : '拖动移动光标\n上下拖 = 跨行',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 10,
                      height: 1.6,
                      color: Color(0xFF4D5763),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
