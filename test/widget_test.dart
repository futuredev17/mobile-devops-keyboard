import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geek_console_demo/geek/geek_editing_engine.dart';

void main() {
  late TextEditingController controller;
  late GeekEditingEngine engine;

  setUp(() {
    controller = TextEditingController(text: 'echo hi');
    controller.selection = const TextSelection.collapsed(offset: 7);
    engine = GeekEditingEngine(controller, tab: '    ');
  });

  tearDown(() => controller.dispose());

  test('在光标处插入，而不是拼在末尾', () {
    controller.selection = const TextSelection.collapsed(offset: 4);
    engine.insert('~');
    expect(controller.text, 'echo~ hi');
    expect(controller.selection.baseOffset, 5);
  });

  test('有选区时插入会替换选区', () {
    controller.selection =
        const TextSelection(baseOffset: 0, extentOffset: 4);
    engine.insert('ls');
    expect(controller.text, 'ls hi');
    expect(controller.selection.baseOffset, 2);
  });

  test('退格删除光标前一个字符', () {
    engine.backspace();
    expect(controller.text, 'echo h');
    expect(controller.selection.baseOffset, 6);
  });

  test('Ctrl+退格整词删除', () {
    engine.backspace(byWord: true);
    expect(controller.text, 'echo ');
    expect(controller.selection.baseOffset, 5);
  });

  test('方向键移动光标，Shift+方向键扩选', () {
    engine.moveLeft();
    expect(controller.selection.baseOffset, 6);
    engine.moveLeft(extend: true);
    expect(controller.selection.start, 5);
    expect(controller.selection.end, 6);
  });

  test('Ctrl+左键按词跳转', () {
    engine.moveLeft(byWord: true);
    expect(controller.selection.baseOffset, 5);
  });

  test('Tab 插入缩进', () {
    engine.moveLineStart();
    engine.insertTab();
    expect(controller.text, '    echo hi');
  });

  test('回车继承当前行缩进', () {
    controller.text = '  foo';
    controller.selection = const TextSelection.collapsed(offset: 5);
    engine.enter();
    expect(controller.text, '  foo\n  ');
    expect(controller.selection.baseOffset, 8);
  });

  test('上下键按列移动', () {
    controller.text = 'abcd\nefgh';
    controller.selection = const TextSelection.collapsed(offset: 2);
    engine.moveDown();
    expect(controller.selection.baseOffset, 7);
    engine.moveUp();
    expect(controller.selection.baseOffset, 2);
  });

  test('撤销回到上一步', () {
    engine.insert('!');
    expect(controller.text, 'echo hi!');
    engine.undo();
    expect(controller.text, 'echo hi');
  });
}
