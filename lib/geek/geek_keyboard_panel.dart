import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cursor_trackpad.dart';
import 'geek_editing_engine.dart';
import 'geek_keys.dart';
import 'ui_bits.dart';

/// 整套键盘：左侧 2/3 是键区，右侧 1/3 是光标触摸区。
class GeekKeyboardPanel extends StatefulWidget {
  const GeekKeyboardPanel({
    super.key,
    required this.engine,
    required this.locked,
    required this.caretVisible,
    required this.floating,
    required this.onToggleLock,
    required this.onToggleCaret,
    required this.onToggleMode,
    required this.onHide,
  });

  final GeekEditingEngine engine;
  final bool locked;
  final bool caretVisible;
  final bool floating;

  final VoidCallback onToggleLock;
  final VoidCallback onToggleCaret;
  final VoidCallback onToggleMode;
  final VoidCallback onHide;

  @override
  State<GeekKeyboardPanel> createState() => _GeekKeyboardPanelState();
}

class _GeekKeyboardPanelState extends State<GeekKeyboardPanel> {
  bool _shift = false;
  bool _ctrl = false;
  bool _sym = false;

  // ------------------------------------------------------------------ 构建

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kPanelBg,
      child: Column(
        children: <Widget>[
          _header(),
          const Divider(height: 1, thickness: 0.6, color: kPanelBorder),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 5, 6, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(flex: 2, child: _keyboardArea()),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 1,
                    child: CursorTrackpad(
                      engine: widget.engine,
                      caretVisible: widget.caretVisible,
                      onToggleCaret: widget.onToggleCaret,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return SizedBox(
      height: 30,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: widget.locked
                    ? kAccent
                    : const Color(0xFFB62324),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                widget.locked ? 'EN · LOCKED' : 'IME · UNLOCKED',
                style: const TextStyle(
                  fontSize: 9.5,
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 6),
            MiniChip(
              label: widget.locked ? '解锁输入法' : '锁死英文',
              onTap: widget.onToggleLock,
              active: widget.locked,
            ),
            const SizedBox(width: 5),
            MiniChip(
              label: widget.caretVisible ? '隐藏光标' : '显示光标',
              onTap: widget.onToggleCaret,
              active: widget.caretVisible,
            ),
            const SizedBox(width: 5),
            MiniChip(
              label: widget.floating ? '停靠底部' : '变悬浮窗',
              onTap: widget.onToggleMode,
            ),
            const SizedBox(width: 5),
            MiniChip(label: '收起', onTap: widget.onHide),
            const SizedBox(width: 8),
            Text(
              _sym ? 'SYM · 符号页' : (_shift ? 'SHIFT' : 'US ANSI'),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 9,
                color: kTextDim,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _keyboardArea() {
    final List<List<GeekKeyDef>> rows = <List<GeekKeyDef>>[
      ...(_sym ? GeekLayouts.symRows : GeekLayouts.mainRows),
      GeekLayouts.bottomRow,
    ];

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        const double gap = 4;
        final double rowH =
            (c.maxHeight - gap * (rows.length - 1)) / rows.length;
        final double font = (rowH * 0.36).clamp(8.0, 16.0).toDouble();

        return Column(
          children: <Widget>[
            for (int i = 0; i < rows.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: gap),
              SizedBox(
                height: rowH < 16 ? 16.0 : rowH,
                child: Row(
                  children: <Widget>[
                    for (int j = 0; j < rows[i].length; j++) ...<Widget>[
                      if (j > 0) const SizedBox(width: gap),
                      Expanded(
                        flex: (rows[i][j].flex * 10).round(),
                        child: _buildKey(rows[i][j], font),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildKey(GeekKeyDef def, double font) {
    final bool active = switch (def.action) {
      GeekKeyAction.shift => _shift,
      GeekKeyAction.ctrl => _ctrl,
      GeekKeyAction.sym => _sym,
      _ => false,
    };
    final bool repeatable = def.action == GeekKeyAction.backspace ||
        def.action == GeekKeyAction.deleteForward ||
        def.action == GeekKeyAction.arrowLeft ||
        def.action == GeekKeyAction.arrowRight ||
        def.action == GeekKeyAction.arrowUp ||
        def.action == GeekKeyAction.arrowDown;

    return KeyCap(
      label: _labelFor(def),
      fontSize: font,
      active: active,
      repeatable: repeatable,
      dim: def.accent && !active,
      onTap: () => _handle(def),
    );
  }

  String _labelFor(GeekKeyDef def) {
    if (_sym && def.action == GeekKeyAction.text) return def.label;
    if (_shift && def.shiftOutput != null) return def.shiftOutput!;
    if (def.action == GeekKeyAction.sym) return _sym ? 'ABC' : '?123';
    return def.label;
  }

  // ------------------------------------------------------------------ 事件

  Future<void> _handle(GeekKeyDef def) async {
    HapticFeedback.selectionClick();
    final GeekEditingEngine e = widget.engine;

    switch (def.action) {
      case GeekKeyAction.shift:
        setState(() => _shift = !_shift);
        return;
      case GeekKeyAction.ctrl:
        setState(() => _ctrl = !_ctrl);
        return;
      case GeekKeyAction.sym:
        setState(() {
          _sym = !_sym;
          _shift = false;
        });
        return;
      case GeekKeyAction.backspace:
        e.backspace(byWord: _ctrl);
        break;
      case GeekKeyAction.deleteForward:
        e.deleteForward(byWord: _ctrl);
        break;
      case GeekKeyAction.tab:
        if (_ctrl) {
          e.indentSelection();
        } else {
          e.insertTab();
        }
        break;
      case GeekKeyAction.enter:
        e.enter();
        break;
      case GeekKeyAction.escape:
        e.clearLine();
        break;
      case GeekKeyAction.space:
        e.insert(' ');
        break;
      case GeekKeyAction.arrowLeft:
        e.moveLeft(extend: _shift, byWord: _ctrl);
        break;
      case GeekKeyAction.arrowRight:
        e.moveRight(extend: _shift, byWord: _ctrl);
        break;
      case GeekKeyAction.arrowUp:
        e.moveUp(extend: _shift);
        break;
      case GeekKeyAction.arrowDown:
        e.moveDown(extend: _shift);
        break;
      case GeekKeyAction.lineStart:
        e.moveLineStart(extend: _shift, toDocumentStart: _ctrl);
        break;
      case GeekKeyAction.lineEnd:
        e.moveLineEnd(extend: _shift, toDocumentEnd: _ctrl);
        break;
      case GeekKeyAction.text:
        final String s = def.resolveText(_shift);
        if (_ctrl && s.length == 1) {
          await _ctrlCombo(s);
        } else {
          e.insert(s);
        }
        break;
    }

    if (!mounted) return;
    if (_shift) setState(() => _shift = false);
    if (_ctrl) setState(() => _ctrl = false);
  }

  Future<void> _ctrlCombo(String ch) async {
    final GeekEditingEngine e = widget.engine;
    switch (ch.toLowerCase()) {
      case 'c':
        await e.copy();
        break;
      case 'x':
        await e.cut();
        break;
      case 'v':
        await e.paste();
        break;
      case 'a':
        e.selectAll();
        break;
      case 'z':
        e.undo();
        break;
      case 'k':
        e.killToLineEnd();
        break;
      case 'u':
        e.clearLine();
        break;
      default:
        break;
    }
  }
}
