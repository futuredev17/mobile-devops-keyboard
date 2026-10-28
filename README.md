# HOLO COMMAND · 全息赛博指挥中心

手机端（Flutter）= 控制器 + WebSocket 服务端；平板/电脑 = 浏览器打开即用的赛博大屏。
平板**不需要装 App**，用浏览器访问 `http://手机IP:8848` 即可。

```
holo_command_center/
├─ assets/holo_dashboard.html      # 平板端单文件大屏（HTML+CSS+JS）
├─ lib/holo/console_server.dart    # WebSocket 服务端 + 状态广播 + 指令接收
└─ lib/holo/holo_link.dart         # 手机端连接指示灯 / 二维码面板
```

---

## 1. 放进你的工程

把文件按同名路径拷进现有项目：

```
你的项目/
├─ assets/holo_dashboard.html
└─ lib/holo/
   ├─ console_server.dart
   └─ holo_link.dart
```

`pubspec.yaml`：

```yaml
dependencies:
  flutter:
    sdk: flutter
  qr_flutter: ^4.1.0

flutter:
  assets:
    - assets/holo_dashboard.html
```

`flutter pub get`。

### 平台配置

**Android** — `AndroidManifest.xml` 里（`<application>` 外）确保有：

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

**iOS** — `Info.plist` 加上（iOS 14+ 访问局域网需要授权弹窗）：

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>用于与同一 Wi-Fi 下的大屏终端建立协同连接</string>
```

**Windows / macOS** — 首次启动会被防火墙询问，放行即可；macOS 还需在
`*.entitlements` 中允许 `com.apple.security.network.server`。

> Flutter Web 无法跑 `dart:io` 服务端，本方案只针对手机/桌面 App。

---

## 2. 接入 console_page.dart

### 2.1 生命周期与回调

```dart
import 'holo/console_server.dart';
import 'holo/holo_link.dart';

class _ConsolePageState extends State<ConsolePage> {
  final _holo = ConsoleServer.instance;

  @override
  void initState() {
    super.initState();

    // 平板点预设 / 发 action
    _holo.onAction = (action) {
      if (action.action == 'preset.run') {
        _runCommand(action.cmd);      // ← 换成你现有的执行方法
      }
    };

    // 平板按回车发命令
    _holo.onRemoteCommand = (cmd) {
      _runCommand(cmd);
    };

    // 平板输入框敲字 → 镜像到手机输入框
    _holo.onRemoteInput = (text) {
      if (!mounted) return;
      setState(() {
        _inputController.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      });
    };
  }

  @override
  void dispose() {
    _holo.onAction = null;
    _holo.onRemoteCommand = null;
    _holo.onRemoteInput = null;
    super.dispose();
  }
}
```

### 2.2 在键盘上方插入状态条

在 `build` 里、键盘组件正上方加一行：

```dart
Column(
  children: [
    Expanded(child: /* 原来的日志/终端区 */),
    const HoloLinkBar(),          // ← 就这一行
    /* 原来的极客键盘 */,
  ],
)
```

### 2.3 广播手机端的动作

在你原来「按键 → 缓冲字符」的地方：

```dart
void _onKeyTap(String ch) {
  _buffer += ch;
  _holo.pushKeystroke(_buffer);          // 实时同步到平板
  _holo.pushCursor(_buffer.length, text: _buffer);
}

void _onBackspace() {
  if (_buffer.isNotEmpty) _buffer = _buffer.substring(0, _buffer.length - 1);
  _holo.pushKeystroke(_buffer);
}

Future<void> _runCommand(String cmd) async {
  _holo.pushLog('phone', r'$ ' + cmd);   // 平板终端立刻看到
  // ...你原来的执行逻辑...
  final output = await _executor.run(cmd);
  _holo.pushOutput(cmd, output);          // 执行结果回传大屏
}
```

### 2.4 手动启停（可选）

状态条右侧开关已经能启停。若想在别处控制：

```dart
final error = await ConsoleServer.instance.start();  // null = 成功
if (error != null) debugPrint(error);
await ConsoleServer.instance.stop();
```

---

## 3. 使用流程

1. 手机打开 App → 点状态条右侧开关 → 服务启动。
2. 自动弹出面板：显示 `http://192.168.x.x:8848` 和二维码。
3. 平板连同一 Wi-Fi → 扫码或手动输入地址 → 大屏亮起。
4. 手机敲键：平板左侧终端实时滚动，右上角图表跳动，延迟显示在 `LAT`。
5. 平板点快捷指令 / 敲命令回车：手机执行，结果再广播回大屏。
6. 状态条变绿灯 + `已连接 1 台大屏`。

---

## 4. 通信协议（想扩展时看这里）

### 手机 → 平板（服务端广播）

| type | 载荷 | 说明 |
|---|---|---|
| `hello` | `role`, `device`, `clients` | 握手 |
| `presets` | `items[]` | 快捷指令列表 |
| `log` | `level`, `text` | 终端日志 |
| `keystroke` | `cmd`, `submit` | 手机键盘实时内容 |
| `state` | `key`, `value` | 任意状态（光标等） |
| `metrics` | `cpu`, `mem`, `net`, `clients`, `uptime` | 每秒一次 |
| `clients` | `count` | 在线设备数 |
| `pong` | `ts` | 延迟回环 |

### 平板 → 手机（服务端接收）

| type | 载荷 | 说明 |
|---|---|---|
| `input` | `data` | 输入框实时内容（90ms 节流） |
| `command` | `data` | 回车下发的命令 |
| `action` | `action`, `payload` | 预设按钮，如 `preset.run` |
| `ping` | `ts` | 2.5s 心跳，用于测延迟 |

预设的下发格式：

```json
{"type":"action","action":"preset.run",
 "payload":{"id":"disk","name":"磁盘巡检","cmd":"df -h"}}
```

`ConsoleServer.presets` 里改这个列表，平板端会自动同步刷新。

---

## 5. 关于「延迟 < 50ms」

局域网内 WebSocket 单程通常在 1–10ms，键盘动作是**逐键立即广播**（无节流）；
只有平板输入框的镜像做了 90ms 节流，避免每敲一个字都刷屏——回车和执行结果不受影响。
大屏右上角的 `LAT` 是 2.5 秒一次 ping 的实测 RTT，可以直接用来验收。

指标面板每秒推一次真实数据，两次推送之间由前端插值补帧，所以曲线看起来是连续流动的。

---

## 6. 排查

| 现象 | 处理 |
|---|---|
| 平板打不开页面 | 确认同一 Wi-Fi；关闭路由器「AP 隔离」；Windows 放行防火墙 |
| 二维码扫了没反应 | 用平板相机扫，或直接在浏览器输入面板上的地址 |
| 显示 `127.0.0.1` | 手机没连 Wi-Fi（只有蜂窝），先连局域网 |
| 端口被占用 | `ConsoleServer.start(port: 8849)` 换端口 |
| 图表在动但没日志 | 手机端没调 `pushKeystroke/pushLog`，或页面没连上（看红点） |
| 杀进程后端口没释放 | `stop()` 已 `force: true`，正常退出即可 |
