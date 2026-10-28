import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 把「按下一个键」翻译成 [TextEditingValue] 的语义修改。
///
/// 这是整套自定义键盘的核心。所有按键都走这里，直接改写
/// [TextEditingController.value]（文本 + 选区 + 光标位置），
/// 所以退格、Tab、方向键、Ctrl+← 的行为和物理键盘完全一致，
/// 而不是 `text += 'x'` 那种拼接字符串的假键盘。
class GeekEditingEngine {
  GeekEditingEngine(this.controller, {this.tab = '    '});

  final TextEditingController controller;

  /// Tab 键插入的内容。写代码用 4 空格；shell 场景可以改成 '\t'。
  final String tab;

  static const int _maxUndo = 200;
  final List<TextEditingValue> _undoStack = <TextEditingValue>[];

  TextEditingValue get value => controller.value;
  String get text => controller.value.text;

  // --------------------------------------------------------------- 基础工具

  TextSelection get _selection {
    final TextSelection s = controller.value.selection;
    if (!s.isValid) return TextSelection.collapsed(offset: text.length);
    return s;
  }

  /// 归一化成 start <= end。
  ({int start, int end}) get _range {
    final TextSelection s = _selection;
    return s.start <= s.end
        ? (start: s.start, end: s.end)
        : (start: s.end, end: s.start);
  }

  static int _clampOffset(int v, int max) => v < 0 ? 0 : (v > max ? max : v);

  void _snapshot() {
    if (_undoStack.length >= _maxUndo) _undoStack.removeAt(0);
    _undoStack.add(controller.value);
  }

  /// 一次提交：直接替换整个 TextEditingValue（含选区），
  /// composing 一律清空，避免残留的系统输入法组字状态。
  void _write(String newText, int caret, {int? selectionEnd}) {
    final int c = _clampOffset(caret, newText.length);
    final int e =
        selectionEnd == null ? c : _clampOffset(selectionEnd, newText.length);
    controller.value = TextEditingValue(
      text: newText,
      selection: e == c
          ? TextSelection.collapsed(offset: c)
          : TextSelection(baseOffset: c, extentOffset: e),
    );
  }

  void _moveTo(int offset, {required bool extend, required int anchor}) {
    final int target = _clampOffset(offset, text.length);
    final int safeAnchor = _clampOffset(anchor, text.length);
    controller.value = controller.value.copyWith(
      selection: extend
          ? TextSelection(baseOffset: safeAnchor, extentOffset: target)
          : TextSelection.collapsed(offset: target),
      composing: TextRange.empty,
    );
  }

  // --------------------------------------------------------------- 文本编辑

  /// 在光标处插入任意字符串（单字符、多字符宏命令都走这里）。
  /// 有选区时替换选区——和物理键盘一致。
  void insert(String s) {
    if (s.isEmpty) return;
    final r = _range;
    _snapshot();
    _write(text.replaceRange(r.start, r.end, s), r.start + s.length);
  }

  void backspace({bool byWord = false}) {
    final r = _range;
    if (r.start != r.end) {
      _snapshot();
      _write(text.replaceRange(r.start, r.end, ''), r.start);
      return;
    }
    if (r.start == 0) return;
    _snapshot();
    final int from =
        byWord ? _wordLeft(text, r.start) : _prevIndex(text, r.start);
    _write(text.replaceRange(from, r.start, ''), from);
  }

  void deleteForward({bool byWord = false}) {
    final r = _range;
    if (r.start != r.end) {
      _snapshot();
      _write(text.replaceRange(r.start, r.end, ''), r.start);
      return;
    }
    if (r.end >= text.length) return;
    _snapshot();
    final int to =
        byWord ? _wordRight(text, r.end) : _nextIndex(text, r.end);
    _write(text.replaceRange(r.end, to, ''), r.end);
  }

  void insertTab() => insert(tab);

  /// 有选区时按 Tab 整体缩进（代码编辑器行为）。
  void indentSelection() {
    final r = _range;
    if (r.start == r.end) {
      insert(tab);
      return;
    }
    final int blockStart = _lineStart(text, r.start);
    final String block = text.substring(blockStart, r.end);
    final String replaced =
        block.split('\n').map((String l) => '$tab$l').join('\n');
    _snapshot();
    final String newText = text.replaceRange(blockStart, r.end, replaced);
    _write(newText, blockStart,
        selectionEnd: r.end + (replaced.length - block.length));
  }

  /// 回车 + 自动继承当前行缩进。
  void enter() {
    final r = _range;
    final int lineStart = _lineStart(text, r.start);
    final String head = text.substring(lineStart, r.start);
    final RegExpMatch? m = RegExp(r'^[ \t]*').firstMatch(head);
    insert('\n${m?.group(0) ?? ''}');
  }

  /// 清空当前行（映射到 Esc / Ctrl+U 这类“中断当前命令”的直觉）。
  void clearLine() {
    final r = _range;
    final int start = _lineStart(text, r.start);
    final int end = _lineEnd(text, r.end);
    if (start >= end) return;
    _snapshot();
    _write(text.replaceRange(start, end, ''), start);
  }

  /// Ctrl+K
  void killToLineEnd() {
    final r = _range;
    final int end = _lineEnd(text, r.end);
    if (r.start >= end) return;
    _snapshot();
    _write(text.replaceRange(r.start, end, ''), r.start);
  }

  // --------------------------------------------------------------- 光标移动

  void moveLeft({bool extend = false, bool byWord = false}) {
    final TextSelection sel = _selection;
    final r = _range;
    if (!extend && r.start != r.end) {
      _moveTo(r.start, extend: false, anchor: sel.baseOffset);
      return;
    }
    final int from = extend ? sel.extentOffset : r.start;
    final int target =
        byWord ? _wordLeft(text, from) : _prevIndex(text, from);
    _moveTo(target, extend: extend, anchor: sel.baseOffset);
  }

  void moveRight({bool extend = false, bool byWord = false}) {
    final TextSelection sel = _selection;
    final r = _range;
    if (!extend && r.start != r.end) {
      _moveTo(r.end, extend: false, anchor: sel.baseOffset);
      return;
    }
    final int from = extend ? sel.extentOffset : r.end;
    final int target =
        byWord ? _wordRight(text, from) : _nextIndex(text, from);
    _moveTo(target, extend: extend, anchor: sel.baseOffset);
  }

  /// 上下键：按“行 + 列”移动，列尽量保持（跨行更符合物理键盘手感）。
  void moveUp({bool extend = false}) {
    final TextSelection sel = _selection;
    final int from = sel.extentOffset;
    final int lineStart = _lineStart(text, from);
    if (lineStart == 0) {
      _moveTo(0, extend: extend, anchor: sel.baseOffset);
      return;
    }
    final int column = from - lineStart;
    final int prevEnd = lineStart - 1; // 上一行结尾的 '\n' 所在位置
    final int prevStart = _lineStart(text, prevEnd);
    _moveTo(prevStart + column, extend: extend, anchor: sel.baseOffset);
  }

  void moveDown({bool extend = false}) {
    final TextSelection sel = _selection;
    final int from = sel.extentOffset;
    final int lineStart = _lineStart(text, from);
    final int lineEnd = _lineEnd(text, from);
    if (lineEnd >= text.length) {
      _moveTo(text.length, extend: extend, anchor: sel.baseOffset);
      return;
    }
    final int column = from - lineStart;
    _moveTo(lineEnd + 1 + column, extend: extend, anchor: sel.baseOffset);
  }

  void moveLineStart({bool extend = false, bool toDocumentStart = false}) {
    final TextSelection sel = _selection;
    final int target =
        toDocumentStart ? 0 : _lineStart(text, sel.extentOffset);
    _moveTo(target, extend: extend, anchor: sel.baseOffset);
  }

  void moveLineEnd({bool extend = false, bool toDocumentEnd = false}) {
    final TextSelection sel = _selection;
    final int target =
        toDocumentEnd ? text.length : _lineEnd(text, sel.extentOffset);
    _moveTo(target, extend: extend, anchor: sel.baseOffset);
  }

  // --------------------------------------------------------------- 选区/剪贴板

  void selectAll() {
    controller.value = controller.value.copyWith(
      selection: TextSelection(baseOffset: 0, extentOffset: text.length),
      composing: TextRange.empty,
    );
  }

  Future<void> copy() async {
    final r = _range;
    if (r.start == r.end) return;
    await Clipboard.setData(
      ClipboardData(text: text.substring(r.start, r.end)),
    );
  }

  Future<void> cut() async {
    final r = _range;
    if (r.start == r.end) return;
    await Clipboard.setData(
      ClipboardData(text: text.substring(r.start, r.end)),
    );
    backspace();
  }

  Future<void> paste() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    final String? s = data?.text;
    if (s == null || s.isEmpty) return;
    insert(s);
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    controller.value = _undoStack.removeLast();
  }

  // --------------------------------------------------------------- 静态工具

  static int _lineStart(String t, int index) {
    if (index <= 0) return 0;
    final int i = t.lastIndexOf('\n', index - 1);
    return i < 0 ? 0 : i + 1;
  }

  static int _lineEnd(String t, int index) {
    final int i = t.indexOf('\n', _clampOffset(index, t.length));
    return i < 0 ? t.length : i;
  }

  /// 按 UTF-16 码元退一格，避开代理对（emoji）被劈成半个字符。
  static int _prevIndex(String t, int i) {
    if (i <= 0) return 0;
    final int unit = t.codeUnitAt(i - 1);
    if (unit >= 0xDC00 && unit <= 0xDFFF && i >= 2) {
      final int prev = t.codeUnitAt(i - 2);
      if (prev >= 0xD800 && prev <= 0xDBFF) return i - 2;
    }
    return i - 1;
  }

  static int _nextIndex(String t, int i) {
    if (i >= t.length) return t.length;
    final int unit = t.codeUnitAt(i);
    if (unit >= 0xD800 && unit <= 0xDBFF && i + 1 < t.length) {
      final int next = t.codeUnitAt(i + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) return i + 2;
    }
    return i + 1;
  }

  static final RegExp _wordChar = RegExp(r'[A-Za-z0-9_.~/$-]');

  static bool _isWord(String c) => _wordChar.hasMatch(c);

  static int _wordLeft(String t, int i) {
    int j = i;
    while (j > 0 && !_isWord(t[j - 1])) {
      j--;
    }
    while (j > 0 && _isWord(t[j - 1])) {
      j--;
    }
    return j;
  }

  static int _wordRight(String t, int i) {
    int j = i;
    while (j < t.length && !_isWord(t[j])) {
      j++;
    }
    while (j < t.length && _isWord(t[j])) {
      j++;
    }
    return j;
  }
}
