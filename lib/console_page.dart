import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'geek/geek_editing_engine.dart';
import 'geek/geek_keyboard_panel.dart';

import 'holo/console_server.dart';
import 'holo/holo_link.dart';

enum KeyboardMode { hidden, docked, floating }

class ConsolePage extends StatefulWidget {
  const ConsolePage({super.key});

  @override
  State<ConsolePage> createState() => _ConsolePageState();
}

class _ConsolePageState extends State<ConsolePage> {
  final TextEditingController _controller = TextEditingController(
    text: '# Geek Console · 极客键盘 Demo\n'
        '# 试试：Tab 缩进 · Ctrl+← 跳词 · ↑↓ 跨行 · ?123 里找 | ~ \$ /\n'
        '\$ ',
  );
  final FocusNode _focusNode = FocusNode(debugLabel: 'geek-console');
  late final GeekEditingEngine _engine =
      GeekEditingEngine(_controller, tab: '    ');

  KeyboardMode _mode = KeyboardMode.docked;
  bool _locked = true;
  bool _caretVisible = true;
  final bool _autoLandscape = true;

  Offset? _fabPos;
  Offset _floatPos = const Offset(120, 70);

  @override
  void initState() {
    super.initState();
    // 监听输入框文字变化，实时同步给大屏
    _controller.addListener(() {
      ConsoleServer.instance.pushKeystroke(_controller.text);
    });
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    // --- 加入全息大屏联动回调 ---
    ConsoleServer.instance.onAction = (a) {
      if (a.action == 'preset.run') {
        // 这里假设你原本执行命令的函数叫 _runCommand
        // 如果叫别的名字，请换成你自己的
       // _runCommand(a.cmd);
      }
    };

    ConsoleServer.instance.onRemoteCommand = (cmd) {
     // _runCommand(cmd);
    };

    ConsoleServer.instance.onRemoteInput = (text) {
      // 把大屏发来的文字，同步显示在你的输入框里
      _controller.text = text;
      _controller.selection = TextSelection.collapsed(offset: text.length);
    };
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _focusNode.dispose();
    _controller.dispose();
    // 关闭并清理大屏服务
    ConsoleServer.instance.stop();
    super.dispose();
  }

  // ------------------------------------------------------------------ 模式

  Future<void> _setMode(KeyboardMode mode) async {
    if (_mode == mode) return;
    setState(() => _mode = mode);

    if (_autoLandscape) {
      if (mode == KeyboardMode.hidden) {
        await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      } else {
        await SystemChrome.setPreferredOrientations(
          const <DeviceOrientation>[
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ],
        );
      }
    }
    if (!mounted) return;
    if (mode != KeyboardMode.hidden) _focusNode.requestFocus();
  }

  void _toggleLock() {
    setState(() => _locked = !_locked);
    if (_locked) {
      // readOnly 变回 true 时 Flutter 会主动断开输入法连接，系统键盘随即收起。
      _focusNode.requestFocus();
      _showHint('已锁死：只能走极客键盘，系统输入法被屏蔽');
    } else {
      _focusNode.requestFocus();
      _showHint('已解锁：系统输入法接管，可能自动切到中文');
    }
  }

  void _showHint(String msg) {
    final ScaffoldMessengerState? m = ScaffoldMessenger.maybeOf(context);
    if (m == null) return;
    m.hideCurrentSnackBar();
    m.showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 12)),
        duration: const Duration(milliseconds: 1600),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ------------------------------------------------- 真实硬件键盘（可选加分项）

  bool _onHardwareKey(KeyEvent event) {
    if (!_locked) return false; // 解锁状态交给系统输入法处理
    if (event is KeyUpEvent) return false;

    final LogicalKeyboardKey k = event.logicalKey;
    final bool ctrl = HardwareKeyboard.instance.isControlPressed;
    final bool shift = HardwareKeyboard.instance.isShiftPressed;

    if (k == LogicalKeyboardKey.backspace) {
      _engine.backspace(byWord: ctrl);
      return true;
    }
    if (k == LogicalKeyboardKey.delete) {
      _engine.deleteForward(byWord: ctrl);
      return true;
    }
    if (k == LogicalKeyboardKey.tab) {
      _engine.insertTab();
      return true;
    }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      _engine.enter();
      return true;
    }
    if (k == LogicalKeyboardKey.escape) {
      _engine.clearLine();
      return true;
    }
    if (k == LogicalKeyboardKey.arrowLeft) {
      _engine.moveLeft(extend: shift, byWord: ctrl);
      return true;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      _engine.moveRight(extend: shift, byWord: ctrl);
      return true;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      _engine.moveUp(extend: shift);
      return true;
    }
    if (k == LogicalKeyboardKey.arrowDown) {
      _engine.moveDown(extend: shift);
      return true;
    }
    if (k == LogicalKeyboardKey.home) {
      _engine.moveLineStart(extend: shift);
      return true;
    }
    if (k == LogicalKeyboardKey.end) {
      _engine.moveLineEnd(extend: shift);
      return true;
    }
    if (ctrl) {
      if (k == LogicalKeyboardKey.keyC) _engine.copy();
      if (k == LogicalKeyboardKey.keyX) _engine.cut();
      if (k == LogicalKeyboardKey.keyV) _engine.paste();
      if (k == LogicalKeyboardKey.keyA) _engine.selectAll();
      if (k == LogicalKeyboardKey.keyZ) _engine.undo();
      return true;
    }

    final String? ch = event.character;
    if (ch != null && ch.isNotEmpty && ch.codeUnitAt(0) >= 0x20) {
      _engine.insert(ch);
      return true;
    }
    return false;
  }

  // ------------------------------------------------------------------ 构建

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    final double dockH = (size.height * 0.62).clamp(170.0, 420.0).toDouble();

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Column(
              children: <Widget>[
                const HoloLinkBar(),
                Expanded(child: _buildEditor()),
                if (_mode == KeyboardMode.docked)
                  SizedBox(
                    height: dockH,
                    child: _buildPanel(floating: false),
                  ),
              ],
            ),
            if (_mode == KeyboardMode.floating) _buildFloatingWindow(size),
            _buildFab(size),
          ],
        ),
      ),
    );
  }

  Widget _buildPanel({required bool floating}) {
    // 任何一次点击都保证输入框仍持有焦点，光标不会因为点键盘而消失。
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        if (!_focusNode.hasFocus) _focusNode.requestFocus();
      },
      child: GeekKeyboardPanel(
        engine: _engine,
        locked: _locked,
        caretVisible: _caretVisible,
        floating: floating,
        onToggleLock: _toggleLock,
        onToggleCaret: () => setState(() => _caretVisible = !_caretVisible),
        onToggleMode: () => _setMode(
          floating ? KeyboardMode.docked : KeyboardMode.floating,
        ),
        onHide: () => _setMode(KeyboardMode.hidden),
      ),
    );
  }

  Widget _buildEditor() {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 6),
          child: Row(
            children: <Widget>[
              const Icon(Icons.terminal, size: 18, color: Color(0xFF58A6FF)),
              const SizedBox(width: 8),
              const Text(
                '极客运维控制台',
                style: TextStyle(
                  color: Color(0xFFE6EDF3),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              _StatusPill(
                text: _locked ? 'EN LOCKED' : 'IME OPEN',
                color: _locked ? kPillBlue : kPillRed,
                onTap: _toggleLock,
              ),
              const SizedBox(width: 6),
              _StatusPill(
                text: _caretVisible ? '光标 ON' : '光标 OFF',
                color: const Color(0xFF30363D),
                onTap: () => setState(() => _caretVisible = !_caretVisible),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0B0F14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF30363D)),
            ),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              // ★ 核心：readOnly = true 会彻底关掉系统输入法连接，
              //   既不会弹软键盘，也不会被切到中文；编辑全部由引擎接管。
              readOnly: _locked,
              showCursor: _caretVisible,
              cursorWidth: _caretVisible ? 2 : 0,
              cursorColor: const Color(0xFF58A6FF),
              cursorRadius: const Radius.circular(1),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                height: 1.5,
                color: Color(0xFFC9D1D9),
              ),
              minLines: null,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              keyboardType: TextInputType.multiline,
              enableInteractiveSelection: true,
              decoration: const InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: '在此输入命令…',
              ),
            ),
          ),
        ),
        _buildStatusBar(),
      ],
    );
  }

  Widget _buildStatusBar() {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _controller,
      builder: (BuildContext context, TextEditingValue value, Widget? _) {
        final TextSelection sel = value.selection;
        final int raw =
            sel.isValid ? sel.extentOffset : value.text.length;
        final int offset =
            raw < 0 ? 0 : (raw > value.text.length ? value.text.length : raw);
        final String before = value.text.substring(0, offset);
        final int line = '\n'.allMatches(before).length + 1;
        final int lastNl = before.lastIndexOf('\n');
        final int col = offset - (lastNl + 1) + 1;

        return Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.centerLeft,
          child: Text(
            'Ln $line, Col $col   ·   选区 ${sel.start}:${sel.end}   ·   '
            '${_mode.name}   ·   ${_locked ? "EN" : "IME"}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 10.5,
              color: Color(0xFF6E7681),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFloatingWindow(Size size) {
    final double w = math.min(560.0, size.width - 16);
    final double h = math.min(300.0, size.height * 0.55);
    final double maxLeft = math.max(0.0, size.width - w);
    final double maxTop = math.max(0.0, size.height - h);
    final double left = _floatPos.dx.clamp(0.0, maxLeft).toDouble();
    final double top = _floatPos.dy.clamp(0.0, maxTop).toDouble();

    return Positioned(
      left: left,
      top: top,
      width: w,
      height: h,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: const <BoxShadow>[
            BoxShadow(color: Color(0x99000000), blurRadius: 20, offset: Offset(0, 8)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF58A6FF), width: 1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: <Widget>[
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (DragUpdateDetails d) {
                    setState(() {
                      _floatPos = Offset(
                        (_floatPos.dx + d.delta.dx)
                            .clamp(0.0, maxLeft)
                            .toDouble(),
                        (_floatPos.dy + d.delta.dy)
                            .clamp(0.0, maxTop)
                            .toDouble(),
                      );
                    });
                  },
                  child: Container(
                    height: 18,
                    color: const Color(0xFF161B22),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(Icons.drag_indicator,
                            size: 12, color: Color(0xFF6E7681)),
                        Text(
                          ' 拖动悬浮窗 · 点“停靠底部”可收回',
                          style: TextStyle(fontSize: 9, color: Color(0xFF6E7681)),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(child: _buildPanel(floating: true)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFab(Size size) {
    const double d = 48;
    final Offset base = _fabPos ?? Offset(size.width - 64, 70);
    final double maxLeft = math.max(0.0, size.width - d);
    final double maxTop = math.max(0.0, size.height - d);
    final bool open = _mode != KeyboardMode.hidden;

    return Positioned(
      left: base.dx.clamp(0.0, maxLeft).toDouble(),
      top: base.dy.clamp(0.0, maxTop).toDouble(),
      child: GestureDetector(
        onPanUpdate: (DragUpdateDetails dlt) {
          final Offset b = _fabPos ?? base;
          setState(() {
            _fabPos = Offset(
              (b.dx + dlt.delta.dx).clamp(0.0, maxLeft).toDouble(),
              (b.dy + dlt.delta.dy).clamp(0.0, maxTop).toDouble(),
            );
          });
        },
        onTap: () => _setMode(
          open ? KeyboardMode.hidden : KeyboardMode.docked,
        ),
        onLongPress: () => _setMode(
          _mode == KeyboardMode.floating
              ? KeyboardMode.docked
              : KeyboardMode.floating,
        ),
        child: Container(
          width: d,
          height: d,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: <Color>[Color(0xFF1F6FEB), Color(0xFF0B3D91)],
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(color: Color(0x881F6FEB), blurRadius: 14),
            ],
          ),
          child: Icon(
            open ? Icons.keyboard_hide : Icons.keyboard_alt_outlined,
            color: Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }
}

const Color kPillBlue = Color(0xFF1F6FEB);
const Color kPillRed = Color(0xFFB62324);

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.text,
    required this.color,
    required this.onTap,
  });

  final String text;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: const Color(0xFF30363D), width: 0.6),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 10,
            color: Colors.white,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}
