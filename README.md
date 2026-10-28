# 极客专属键盘 Demo（Flutter）

极客运维控制台 · 第一阶段原型：**非系统级 IME**，纯 Flutter 自定义组件内嵌在 App 里。

已验证：`flutter analyze` 无问题，`flutter test` 10 项通过。

---

## 一、先回答你最关心的三个技术问题

### 1. 怎么拦住系统软键盘？

三种做法，结论是 **`readOnly: true`**：

| 方案 | 效果 | 问题 |
| --- | --- | --- |
| `TextField(readOnly: true)` | Flutter 直接不建立 IME 连接，软键盘永不弹出 | 文本得自己改（这正是我们要的） |
| `keyboardType: TextInputType.none` | 部分机型有效 | 平台差异大，不可靠 |
| `TextInput.attach` + 自写 `TextInputClient` | 完全接管，连系统输入法回调都收不到 | 要自己实现光标、选区手柄、无障碍、放大镜…… 维护成本高 |

本 Demo 用第一种。它天然带来「语言锁死」：**没有 IME 连接，就没有拼音候选，也不可能被切到中文**。

解锁时把 `readOnly` 切回 `false`，Flutter 会重新连上系统输入法（变回普通输入框）。这就是 `EN · LOCKED` 开关的实质，逻辑在 `console_page.dart` 的 `_toggleLock()`。

> 真正的**系统级**输入法（在任何 App 里都能用）Flutter 做不到，必须写 Android 原生 `InputMethodService`，再用 MethodChannel 与 Dart 通信。那是第二阶段的事。

### 2. `RawKeyboardListener` 还能用吗？

不能这么用了 —— 它在 Flutter 3.18 之后已废弃，`RawKeyEvent` 体系被 `HardwareKeyboard` 取代。现在的写法：

```dart
HardwareKeyboard.instance.addHandler((KeyEvent event) {
  if (event is KeyUpEvent) return false;
  event.logicalKey;   // LogicalKeyboardKey.arrowLeft ...
  event.character;    // 已按 Shift 处理过的字符
  return true;        // 吃掉这次按键
});
```

Demo 里接了这个，所以外接蓝牙键盘时也能像物理键盘一样编辑（`console_page.dart` 的 `_onHardwareKey`）。
如果只想在某个子树里监听，用 `Focus(onKeyEvent: ...)` 或 `KeyboardListener`，但它们会抢焦点——自定义键盘场景下用全局 handler 更稳。

### 3. 怎么做到「像物理键盘」而不是拼字符串？

**所有按键都翻译成 `TextEditingValue` 的语义修改**，永远不写 `text += 'x'`。

核心是 `GeekEditingEngine`（`lib/geek/geek_editing_engine.dart`）：

```dart
void backspace({bool byWord = false}) {
  final r = _range;                       // 归一化选区
  if (r.start != r.end) {                 // 有选区 → 删选区
    _write(text.replaceRange(r.start, r.end, ''), r.start);
    return;
  }
  final from = byWord ? _wordLeft(text, r.start)   // Ctrl+退格整词删
                      : _prevIndex(text, r.start); // 普通退格，含 emoji 代理对
  _write(text.replaceRange(from, r.start, ''), from);
}
```

`_write()` 一次性替换整个 `TextEditingValue`（文本 + 选区 + 光标），所以：

- 退格在**光标处**删，不是删末尾
- 方向键移动光标，Shift+方向键扩选
- Ctrl+← 按词跳转，Ctrl+Backspace 按词删
- 上下键按「行 + 列」移动（跨行保持列位置）
- Tab 在选区上整体缩进
- 回车自动继承上一行缩进
- 有自建 undo 栈（Ctrl+Z）

键盘 Widget 只负责表达意图：

```dart
enum GeekKeyAction { backspace, tab, enter, arrowLeft, shift, ctrl, sym, text, ... }
```

---

## 二、目录结构

```
lib/
├── main.dart                          # MaterialApp + 深色主题
├── console_page.dart                  # 页面壳：编辑器 / 停靠 / 悬浮窗 / FAB / 硬件键盘
└── geek/
    ├── geek_editing_engine.dart       ★ 按键 → TextEditingValue 的语义引擎
    ├── geek_keys.dart                 ★ 仿 US ANSI 布局 + 符号页 + 命令宏
    ├── geek_keyboard_panel.dart       ★ 键盘主体（2/3 键区 + 1/3 光标板）
    ├── cursor_trackpad.dart           # 光标触摸区（拖动移动 / 扩选）
    └── ui_bits.dart                   # KeyCap（支持长按连发）、MiniChip
```

## 三、功能对照表

| 需求 | 实现 | 位置 |
| --- | --- | --- |
| 仿电脑布局 + 完整符号 | US ANSI 5 行，`?123` 符号页直出 `｜ ~ $ / \ { } [ ]` 等 | `geek_keys.dart` |
| `$ / ~ / |` 高频符号直达 | 符号页第一行，不用按 Shift | `GeekLayouts.symRows` |
| 强制横屏呼出 | 打开键盘 → `setPreferredOrientations(landscape)`；收起恢复 | `_setMode` |
| 语言锁死 | `readOnly` + `EN · LOCKED` 开关 | `_toggleLock` |
| Tab / Ctrl / Esc / ↑↓ | 底部功能键行 + Ctrl 组合（C/X/V/A/Z/K/U） | `bottomRow` / `_ctrlCombo` |
| 长按连发 | 退格、方向键按住 400ms 后 55ms 一次 | `KeyCap` |
| 显示 / 隐藏光标 | 顶部与光标板各一个按钮 | `showCursor` + `cursorWidth` |
| 2/3 键区 + 1/3 光标触摸区 | `Expanded(flex: 2)` : `Expanded(flex: 1)` | `GeekKeyboardPanel` |
| 触摸区移动光标 | 横拖逐字符、纵拖跨行、双击切「选择」扩选 | `CursorTrackpad` |
| 悬浮窗一键切换 | 面板「变悬浮窗」/「停靠底部」，悬浮窗可拖动 | `_buildFloatingWindow` |
| 悬浮球常驻 | 右侧圆形按钮，可拖动；点=开/关，长按=停靠/悬浮切换 | `_buildFab` |

## 四、运行

```bash
cd geek_console_demo
flutter run          # 接 Android 设备或模拟器
flutter test         # 引擎单元测试
```

横屏体验最好：手机横过来，键盘占下方 62%，左边 2/3 敲命令，右边 1/3 用大拇指搓光标。

## 五、下一步可接的地方

1. **SSH 终端**：`geek_editing_engine.dart` 里加一个 `onSubmit` 回调，回车时把整行命令交给 `dartssh2`，输出再回填到只读区域。方向键在远端 shell 里应发 `\x1b[A` 而不是移动本地光标——那时引擎可以加一个「raw 模式」，把按键编码成 ANSI 序列。
2. **端云记忆**：命令历史 + 常用片段可以塞进符号页第四行（现在是写死的 `sudo` / `tail -f` 宏），改成动态数据源即可。
3. **系统级 IME**：Android 原生 `InputMethodService` + MethodChannel，把这里的布局和引擎逻辑搬到原生层复用。注意系统 IME 无法强制横屏，只能做「键盘区域内的紧凑布局」。
4. **多行选区手柄**：如果想要手机原生的选区拖柄，保留 `enableInteractiveSelection: true` 即可，已开启。
