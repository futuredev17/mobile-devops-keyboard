import 'package:flutter/foundation.dart';

/// 一个键的「语义动作」。
///
/// 注意这里没有任何字符串拼接逻辑：键盘只负责表达意图
/// （退格 / Tab / 左移一格 …），真正的编辑交给 GeekEditingEngine。
enum GeekKeyAction {
  text,
  space,
  backspace,
  deleteForward,
  tab,
  enter,
  escape,
  arrowLeft,
  arrowRight,
  arrowUp,
  arrowDown,
  lineStart,
  lineEnd,
  shift,
  ctrl,
  sym,
}

@immutable
class GeekKeyDef {
  const GeekKeyDef({
    required this.label,
    this.shiftOutput,
    this.output,
    this.action = GeekKeyAction.text,
    this.flex = 1,
    this.accent = false,
  });

  /// 键帽上显示的文字。
  final String label;

  /// 按住 Shift 时输出的内容（同时用于显示大写 / 上档符号）。
  final String? shiftOutput;

  /// 实际插入的文本，默认等于 label。宏命令可以在这里放多字符。
  final String? output;

  final GeekKeyAction action;

  /// 宽度权重（相对同一行的其它键）。
  final double flex;

  /// 功能键高亮底色。
  final bool accent;

  String resolveText(bool shift) {
    if (shift && shiftOutput != null) return shiftOutput!;
    return output ?? label;
  }
}

GeekKeyDef _k(
  String label, {
  String? shift,
  String? out,
  double flex = 1,
  bool accent = false,
}) {
  return GeekKeyDef(
    label: label,
    shiftOutput: shift,
    output: out,
    flex: flex,
    accent: accent,
  );
}

GeekKeyDef _fn(String label, GeekKeyAction action, {double flex = 1}) {
  return GeekKeyDef(label: label, action: action, flex: flex, accent: true);
}

/// 仿 US ANSI 物理键盘布局，外加一层符号页和一层命令宏。
class GeekLayouts {
  GeekLayouts._();

  /// 主区 4 行（底下一行功能键共用）。
  static final List<List<GeekKeyDef>> mainRows = <List<GeekKeyDef>>[
    <GeekKeyDef>[
      _k('`', shift: '~'),
      _k('1', shift: '!'),
      _k('2', shift: '@'),
      _k('3', shift: '#'),
      _k('4', shift: r'$'),
      _k('5', shift: '%'),
      _k('6', shift: '^'),
      _k('7', shift: '&'),
      _k('8', shift: '*'),
      _k('9', shift: '('),
      _k('0', shift: ')'),
      _k('-', shift: '_'),
      _k('=', shift: '+'),
      _fn('⌫', GeekKeyAction.backspace, flex: 1.5),
    ],
    <GeekKeyDef>[
      _fn('Tab', GeekKeyAction.tab, flex: 1.5),
      _k('q', shift: 'Q'),
      _k('w', shift: 'W'),
      _k('e', shift: 'E'),
      _k('r', shift: 'R'),
      _k('t', shift: 'T'),
      _k('y', shift: 'Y'),
      _k('u', shift: 'U'),
      _k('i', shift: 'I'),
      _k('o', shift: 'O'),
      _k('p', shift: 'P'),
      _k('[', shift: '{'),
      _k(']', shift: '}'),
      _k('\\', shift: '|'),
    ],
    <GeekKeyDef>[
      _k('a', shift: 'A'),
      _k('s', shift: 'S'),
      _k('d', shift: 'D'),
      _k('f', shift: 'F'),
      _k('g', shift: 'G'),
      _k('h', shift: 'H'),
      _k('j', shift: 'J'),
      _k('k', shift: 'K'),
      _k('l', shift: 'L'),
      _k(';', shift: ':'),
      _k("'", shift: '"'),
      _fn('Enter', GeekKeyAction.enter, flex: 1.8),
    ],
    <GeekKeyDef>[
      _fn('Shift', GeekKeyAction.shift, flex: 1.7),
      _k('z', shift: 'Z'),
      _k('x', shift: 'X'),
      _k('c', shift: 'C'),
      _k('v', shift: 'V'),
      _k('b', shift: 'B'),
      _k('n', shift: 'N'),
      _k('m', shift: 'M'),
      _k(',', shift: '<'),
      _k('.', shift: '>'),
      _k('/', shift: '?'),
      _fn('Shift', GeekKeyAction.shift, flex: 1.7),
    ],
  ];

  /// 符号页：| ~ $ / 这类 shell 高频符号一屏直达，不用再按 Shift。
  static final List<List<GeekKeyDef>> symRows = <List<GeekKeyDef>>[
    <GeekKeyDef>[
      _k('`'),
      _k('~'),
      _k('|'),
      _k(r'$'),
      _k('/'),
      _k('\\'),
      _k(':'),
      _k(';'),
      _k('"'),
      _k("'"),
      _k('?'),
      _k('!'),
    ],
    <GeekKeyDef>[
      _k('@'),
      _k('#'),
      _k('%'),
      _k('^'),
      _k('&'),
      _k('*'),
      _k('('),
      _k(')'),
      _k('['),
      _k(']'),
      _k('{'),
      _k('}'),
    ],
    <GeekKeyDef>[
      _k('-'),
      _k('_'),
      _k('='),
      _k('+'),
      _k(','),
      _k('.'),
      _k('<'),
      _k('>'),
      _k('&&'),
      _k('||'),
      _k('>>'),
      _k('2>&1'),
    ],
    <GeekKeyDef>[
      _k('sudo', out: 'sudo ', flex: 2),
      _k('~/', out: '~/', flex: 2),
      _k('tail -f', out: 'tail -f ', flex: 2),
      _k('| grep', out: '| grep ', flex: 2),
      _k('systemctl', out: 'systemctl ', flex: 2),
      _k('docker', out: 'docker ', flex: 2),
    ],
  ];

  /// 底部功能键行（两种布局共用）。
  static final List<GeekKeyDef> bottomRow = <GeekKeyDef>[
    _fn('Esc', GeekKeyAction.escape, flex: 1.3),
    _fn('Ctrl', GeekKeyAction.ctrl, flex: 1.3),
    _fn('Home', GeekKeyAction.lineStart, flex: 1.5),
    _fn('End', GeekKeyAction.lineEnd, flex: 1.5),
    _fn('←', GeekKeyAction.arrowLeft, flex: 1.2),
    _fn('↑', GeekKeyAction.arrowUp, flex: 1.2),
    _fn('↓', GeekKeyAction.arrowDown, flex: 1.2),
    _fn('→', GeekKeyAction.arrowRight, flex: 1.2),
    _k('space', out: ' ', flex: 5),
    _fn('?123', GeekKeyAction.sym, flex: 1.5),
  ];
}
