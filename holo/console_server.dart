import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 平板端下发的一条动作指令。
///
/// 网页端点击「快捷指令」时发送：
/// ```json
/// {"type":"action","action":"preset.run","payload":{"id":"disk","cmd":"df -h"}}
/// ```
class RemoteAction {
  const RemoteAction(this.action, this.payload);

  final String action;
  final Map<String, dynamic> payload;

  factory RemoteAction.fromJson(Map<String, dynamic> json) {
    final raw = json['payload'];
    return RemoteAction(
      (json['action'] ?? '').toString(),
      raw is Map
          ? raw.map((k, v) => MapEntry(k.toString(), v))
          : const <String, dynamic>{},
    );
  }

  String get id => (payload['id'] ?? '').toString();
  String get name => (payload['name'] ?? '').toString();
  String get cmd => (payload['cmd'] ?? '').toString();
}

typedef HoloActionHandler = void Function(RemoteAction action);
typedef HoloTextHandler = void Function(String text);

/// 内置的局域网协同服务：
/// 1. 在 8848 端口同时提供 HTTP 页面（平板打开即用）与 WebSocket 通道；
/// 2. 把手机端的按键、日志、指标实时广播给所有平板；
/// 3. 接收平板的指令并回调给 App。
///
/// 注意：本服务依赖 `dart:io`，仅支持 Android / iOS / Windows / macOS / Linux，
/// 不支持 Flutter Web。
class ConsoleServer {
  ConsoleServer._();

  static final ConsoleServer instance = ConsoleServer._();

  /// 默认端口。
  static const int defaultPort = 8848;

  /// 平板页面资源路径（需在 pubspec.yaml 中声明）。
  static const String dashboardAsset = 'assets/holo_dashboard.html';

  /// 内置快捷指令，会在平板连上时下发。
  static const List<Map<String, String>> presets = <Map<String, String>>[
    {'id': 'disk', 'icon': '▤', 'name': '磁盘巡检', 'cmd': 'df -h'},
    {'id': 'docker', 'icon': '▣', 'name': '容器总览', 'cmd': 'docker ps -a'},
    {
      'id': 'top',
      'icon': '◈',
      'name': '资源 TOP',
      'cmd': 'ps aux --sort=-%cpu | head -n 10',
    },
    {
      'id': 'nginx',
      'icon': '⟳',
      'name': '重载 Nginx',
      'cmd': 'systemctl reload nginx',
    },
    {'id': 'net', 'icon': '⇄', 'name': '网络探测', 'cmd': 'ping -c 4 1.1.1.1'},
    {'id': 'log', 'icon': '⌫', 'name': '清理日志', 'cmd': 'journalctl --vacuum-time=7d'},
  ];

  // ---------------------------------------------------------------------------
  // 可观察状态（直接给 UI 用）
  // ---------------------------------------------------------------------------

  final ValueNotifier<bool> isRunning = ValueNotifier<bool>(false);
  final ValueNotifier<int> clientCount = ValueNotifier<int>(0);
  final ValueNotifier<String> lanIp = ValueNotifier<String>('127.0.0.1');
  final ValueNotifier<int> port = ValueNotifier<int>(defaultPort);

  /// 最后一次启动失败的原因，供 UI 提示。
  final ValueNotifier<String?> lastError = ValueNotifier<String?>(null);

  /// 平板点击预设 / 发送 action 时触发。
  HoloActionHandler? onAction;

  /// 平板在输入框里敲字时触发（用于镜像到手机输入框）。
  HoloTextHandler? onRemoteInput;

  /// 平板按下回车下发命令时触发。
  HoloTextHandler? onRemoteCommand;

  // ---------------------------------------------------------------------------
  // 内部状态
  // ---------------------------------------------------------------------------

  HttpServer? _server;
  final Set<WebSocket> _clients = <WebSocket>{};
  Timer? _ticker;
  DateTime? _startedAt;
  final Random _rnd = Random();

  double _cpu = 22;
  double _mem = 46;
  double _net = 0.4;

  /// 平板应访问的完整地址，例如 `http://192.168.1.20:8848`。
  String get url => 'http://${lanIp.value}:${port.value}';

  int get _now => DateTime.now().millisecondsSinceEpoch;

  // ---------------------------------------------------------------------------
  // 生命周期
  // ---------------------------------------------------------------------------

  /// 启动服务。返回 `null` 表示成功，否则返回可展示的错误文案。
  Future<String?> start({int port = defaultPort}) async {
    if (isRunning.value) return null;

    try {
      final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _server = server;
      this.port.value = port;
      lanIp.value = await _detectLanIp();
      _startedAt = DateTime.now();
      lastError.value = null;
      isRunning.value = true;

      server.listen(
        _handleRequest,
        onError: (Object e, StackTrace st) {
          debugPrint('[holo] http error: $e');
        },
      );

      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _pushMetrics());

      _log('sys', '全息指挥中心已上线 → $url');
      debugPrint('[holo] listening on $url');
      return null;
    } on SocketException catch (e) {
      final msg = '端口 $port 启动失败：${e.osError?.message ?? e.message}';
      lastError.value = msg;
      debugPrint('[holo] $msg');
      await stop();
      return msg;
    }
  }

  /// 停止服务并断开所有平板。
  Future<void> stop() async {
    _ticker?.cancel();
    _ticker = null;

    final sockets = _clients.toList();
    _clients.clear();
    clientCount.value = 0;

    for (final socket in sockets) {
      try {
        await socket.close(WebSocketStatus.normalClosure, 'server stopped');
      } catch (_) {
        // 已经断开，忽略
      }
    }

    final server = _server;
    _server = null;
    isRunning.value = false;
    _startedAt = null;

    if (server != null) {
      try {
        await server.close(force: true);
      } catch (_) {
        // ignore
      }
    }
  }

  // ---------------------------------------------------------------------------
  // HTTP / WebSocket 入口
  // ---------------------------------------------------------------------------

  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;

    // WebSocket 升级必须在 try/finally 之外完成，否则 response 已被接管。
    if (path == '/ws' && WebSocketTransformer.isUpgradeRequest(request)) {
      try {
        final socket = await WebSocketTransformer.upgrade(request);
        _attach(socket);
      } catch (e) {
        debugPrint('[holo] upgrade failed: $e');
      }
      return;
    }

    try {
      if (path == '/' || path == '/index.html') {
        await _serveDashboard(request.response);
        return;
      }
      if (path == '/health') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'ok': true,
          'clients': clientCount.value,
          'ts': _now,
        }));
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('not found');
    } catch (e) {
      debugPrint('[holo] request error: $e');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write('server error');
      } catch (_) {
        // ignore
      }
    } finally {
      try {
        await request.response.close();
      } catch (_) {
        // ignore
      }
    }
  }

  Future<void> _serveDashboard(HttpResponse response) async {
    try {
      final html = await rootBundle.loadString(dashboardAsset);
      response.headers.contentType = ContentType.html;
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      response.write(html);
    } catch (e) {
      response.statusCode = HttpStatus.internalServerError;
      response.write('dashboard asset missing: $e');
      debugPrint('[holo] asset load failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // 连接管理
  // ---------------------------------------------------------------------------

  void _attach(WebSocket socket) {
    _clients.add(socket);
    clientCount.value = _clients.length;

    _send(socket, {
      'type': 'hello',
      'role': 'controller',
      'device': Platform.operatingSystem,
      'clients': _clients.length,
      'ts': _now,
    });
    _send(socket, {'type': 'presets', 'items': presets});
    broadcast({'type': 'clients', 'count': _clients.length});

    _log('ok', '平板已接入 · 当前通道 ${_clients.length}');

    socket.listen(
          (dynamic data) => _onMessage(socket, data),
      onDone: () => _detach(socket),
      onError: (Object e) {
        debugPrint('[holo] socket error: $e');
        _detach(socket);
      },
      cancelOnError: true,
    );
  }

  void _detach(WebSocket socket) {
    if (!_clients.remove(socket)) return;
    clientCount.value = _clients.length;
    try {
      socket.close();
    } catch (_) {
      // ignore
    }
    broadcast({'type': 'clients', 'count': _clients.length});
    _log('warn', '平板已断开 · 剩余通道 ${_clients.length}');
  }

  void _onMessage(WebSocket socket, dynamic data) {
    if (data is! String) return;

    Map<String, dynamic> msg;
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map) return;
      msg = decoded.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {
      return;
    }

    final type = (msg['type'] ?? '').toString();

    switch (type) {
      case 'ping':
        _send(socket, {'type': 'pong', 'ts': msg['ts']});
        return;

      case 'input':
        final text = (msg['data'] ?? '').toString();
        onRemoteInput?.call(text);
        // 同步给其他平板（不回发给发送者，避免回环）
        broadcast(
          {'type': 'mirror', 'source': 'tablet', 'data': text},
          except: socket,
        );
        return;

      case 'command':
        final cmd = (msg['data'] ?? '').toString().trim();
        if (cmd.isEmpty) return;
        _log('tablet', r'$ ' + cmd);
        onRemoteCommand?.call(cmd);
        return;

      case 'action':
        final action = RemoteAction.fromJson(msg);
        if (action.action.isEmpty) return;
        _log('tablet', '▸ ${action.action} ${action.name}'.trim());
        onAction?.call(action);
        return;

      case 'hello':
        return;

      default:
        return;
    }
  }

  // ---------------------------------------------------------------------------
  // 广播 API（手机端 UI 调用这些方法）
  // ---------------------------------------------------------------------------

  /// 广播一条日志到所有平板。
  ///
  /// level 建议值：`sys` / `ok` / `info` / `warn` / `error` / `cmd` / `phone`
  void pushLog(String level, String text) {
    broadcast({
      'type': 'log',
      'level': level,
      'text': text,
      'ts': _now,
    });
  }

  /// 广播手机端键盘当前输入的内容（每次按键、退格都可调用）。
  void pushKeystroke(String text, {bool submit = false}) {
    broadcast({
      'type': 'keystroke',
      'cmd': text,
      'submit': submit,
      'ts': _now,
    });
  }

  /// 广播光标位置，用于平板端还原输入进度。
  void pushCursor(int index, {String text = ''}) {
    broadcast({
      'type': 'state',
      'key': 'cursor',
      'value': {'index': index, 'text': text},
      'ts': _now,
    });
  }

  /// 广播任意命名状态（服务器信息、当前页面、执行状态等）。
  void pushState(String key, Object? value) {
    broadcast({'type': 'state', 'key': key, 'value': value, 'ts': _now});
  }

  /// 手机端执行完命令后，把结果推给平板。
  void pushOutput(String cmd, String output) {
    pushLog('cmd', r'$ ' + cmd);
    if (output.isNotEmpty) pushLog('info', output);
  }

  /// 更新平板上的预设列表。
  void pushPresets(List<Map<String, String>> items) {
    broadcast({'type': 'presets', 'items': items});
  }

  void broadcast(Map<String, dynamic> message, {WebSocket? except}) {
    if (_clients.isEmpty) return;
    final raw = jsonEncode(message);
    for (final socket in _clients.toList()) {
      if (identical(socket, except)) continue;
      _writeRaw(socket, raw);
    }
  }

  void _send(WebSocket socket, Map<String, dynamic> message) {
    _writeRaw(socket, jsonEncode(message));
  }

  void _writeRaw(WebSocket socket, String raw) {
    if (socket.readyState != WebSocket.open) return;
    try {
      socket.add(raw);
    } catch (_) {
      // 连接已断，交给 onDone 处理
    }
  }

  void _log(String level, String text) => pushLog(level, text);

  // ---------------------------------------------------------------------------
  // 假数据指标（真机上可替换为真实采集）
  // ---------------------------------------------------------------------------

  void _pushMetrics() {
    _cpu = _walk(_cpu, 6, 4, 96);
    _mem = _walk(_mem, 3, 28, 92);
    _net = _walk(_net, 0.7, 0, 9);

    broadcast({
      'type': 'metrics',
      'cpu': double.parse(_cpu.toStringAsFixed(1)),
      'mem': double.parse(_mem.toStringAsFixed(1)),
      'net': double.parse(_net.toStringAsFixed(2)),
      'clients': _clients.length,
      'uptime': _startedAt == null
          ? 0
          : DateTime.now().difference(_startedAt!).inSeconds,
      'ts': _now,
    });
  }

  double _walk(double value, double step, double min, double max) {
    final next = value + (_rnd.nextDouble() * 2 - 1) * step;
    if (next < min) return min + _rnd.nextDouble() * step;
    if (next > max) return max - _rnd.nextDouble() * step;
    return next;
  }

  // ---------------------------------------------------------------------------
  // 局域网 IP 探测
  // ---------------------------------------------------------------------------

  Future<String> _detectLanIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );

      String? best;
      var bestScore = -1;

      for (final iface in interfaces) {
        final nameScore =
        RegExp(r'wlan|wifi|wi-fi|en0|eth', caseSensitive: false)
            .hasMatch(iface.name)
            ? 2
            : 0;

        for (final addr in iface.addresses) {
          final ip = addr.address;
          var score = nameScore;

          if (ip.startsWith('192.168.')) {
            score += 30;
          } else if (ip.startsWith('10.')) {
            score += 20;
          } else if (RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip)) {
            score += 15;
          } else {
            score += 1;
          }

          if (score > bestScore) {
            bestScore = score;
            best = ip;
          }
        }
      }

      return best ?? '127.0.0.1';
    } catch (_) {
      return '127.0.0.1';
    }
  }
}
