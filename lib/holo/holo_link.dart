import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'console_server.dart';

const Color _neon = Color(0xFF00FF9C);
const Color _cyan = Color(0xFF22E6FF);
const Color _crimson = Color(0xFFFF3B5C);
const Color _ink = Color(0xFF080D0B);
const Color _dim = Color(0xFF6C877F);

/// 键盘上方的「全息链路」状态条。
///
/// - 绿点：已有平板接入
/// - 红点：未连接 / 未启动
/// - 点二维码图标：弹出局域网地址 + 二维码
/// - 右侧开关：一键启停 WebSocket 服务
class HoloLinkBar extends StatelessWidget {
  const HoloLinkBar({super.key});

  @override
  Widget build(BuildContext context) {
    final server = ConsoleServer.instance;

    return ValueListenableBuilder<bool>(
      valueListenable: server.isRunning,
      builder: (context, running, _) {
        return ValueListenableBuilder<int>(
          valueListenable: server.clientCount,
          builder: (context, count, __) {
            final linked = running && count > 0;
            final color = linked ? _neon : _crimson;
            final label = !running
                ? '未启用'
                : (linked ? '已连接 $count 台大屏' : '等待平板接入');

            return Container(
              margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _ink,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withOpacity(0.45)),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.12),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Row(
                children: [
                  _PulseDot(color: color, active: linked),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Text(
                              'HOLO LINK',
                              style: TextStyle(
                                fontSize: 11,
                                letterSpacing: 2,
                                fontWeight: FontWeight.w700,
                                color: color,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                label,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: _dim,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (running)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '${server.lanIp.value}:${server.port.value}',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF4C6F66),
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => HoloLinkSheet.show(context),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        Icons.qr_code_2,
                        size: 21,
                        color: linked ? _neon : _cyan,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Switch(
                    value: running,
                    activeColor: _neon,
                    activeTrackColor: _neon.withOpacity(0.35),
                    inactiveThumbColor: _crimson,
                    inactiveTrackColor: _crimson.withOpacity(0.2),
                    onChanged: (value) => _toggle(context, server, value),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _toggle(
      BuildContext context,
      ConsoleServer server,
      bool value,
      ) async {
    if (value) {
      final error = await server.start();
      if (!context.mounted) return;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
        return;
      }
      if (context.mounted) await HoloLinkSheet.show(context);
    } else {
      await server.stop();
    }
  }
}

/// 弹出面板：局域网地址、二维码、连接数、启停按钮。
class HoloLinkSheet extends StatelessWidget {
  const HoloLinkSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const HoloLinkSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final server = ConsoleServer.instance;

    return ValueListenableBuilder<bool>(
      valueListenable: server.isRunning,
      builder: (context, running, _) {
        return ValueListenableBuilder<int>(
          valueListenable: server.clientCount,
          builder: (context, count, __) {
            final url = server.url;
            return Container(
              decoration: const BoxDecoration(
                color: _ink,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(
                  top: BorderSide(color: Color(0xFF16302A)),
                ),
              ),
              padding: EdgeInsets.fromLTRB(
                20,
                10,
                20,
                20 + MediaQuery.of(context).padding.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFF20342F),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Text(
                          'HOLO LINK',
                          style: TextStyle(
                            color: _neon,
                            fontSize: 15,
                            letterSpacing: 4,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        _StatusBadge(running: running, count: count),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '手机与平板连接同一个 Wi-Fi，用平板浏览器扫码或输入地址，即可接管主脑大屏。',
                      style: TextStyle(fontSize: 12, height: 1.7, color: _dim),
                    ),
                    const SizedBox(height: 18),
                    if (running) ...[
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: QrImageView(
                            data: url,
                            version: QrVersions.auto,
                            size: 186,
                            backgroundColor: Colors.white,
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _UrlRow(url: url),
                      const SizedBox(height: 8),
                      Text(
                        count > 0
                            ? '当前已有 $count 台设备在线，手机按键会实时广播。'
                            : '服务已就绪，等待平板接入…',
                        style: const TextStyle(fontSize: 11, color: _dim),
                      ),
                    ] else ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 34),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0C1512),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF1A2B26),
                          ),
                        ),
                        child: const Column(
                          children: [
                            Icon(Icons.wifi_off_rounded,
                                color: _crimson, size: 30),
                            SizedBox(height: 8),
                            Text(
                              '局域网服务未启动',
                              style: TextStyle(fontSize: 12, color: _dim),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor:
                              running ? const Color(0xFF3A1418) : _neon,
                              foregroundColor:
                              running ? _crimson : Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                            ),
                            onPressed: () async {
                              if (running) {
                                await server.stop();
                              } else {
                                final error = await server.start();
                                if (error != null && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(error)),
                                  );
                                }
                              }
                            },
                            icon: Icon(
                              running
                                  ? Icons.stop_circle_outlined
                                  : Icons.play_circle_outline,
                              size: 18,
                            ),
                            label: Text(
                              running ? '停止服务' : '启动服务',
                              style: const TextStyle(
                                fontSize: 12,
                                letterSpacing: 2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '提示：平板打不开时，先确认两者在同一网段；'
                          'Windows / macOS 首次启动可能被防火墙拦截，请放行 8080 端口。',
                      style: TextStyle(
                        fontSize: 10,
                        height: 1.7,
                        color: Color(0xFF4C6F66),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _UrlRow extends StatelessWidget {
  const _UrlRow({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1512),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1A2B26)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lan_outlined, size: 16, color: _cyan),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              url,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFFE6FFF8),
                fontFamily: 'monospace',
                letterSpacing: 0.5,
              ),
            ),
          ),
          IconButton(
            tooltip: '复制地址',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy_rounded, size: 16, color: _dim),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('地址已复制')),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.running, required this.count});

  final bool running;
  final int count;

  @override
  Widget build(BuildContext context) {
    final linked = running && count > 0;
    final color = linked ? _neon : (running ? _cyan : _crimson);
    final text = !running ? 'OFFLINE' : (linked ? 'ONLINE $count' : 'STANDBY');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          letterSpacing: 1.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color, required this.active});

  final Color color;
  final bool active;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _PulseDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              if (widget.active)
                Container(
                  width: 8 + 14 * t,
                  height: 8 + 14 * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.color.withOpacity((1 - t) * 0.6),
                    ),
                  ),
                ),
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withValues(
                        alpha: widget.active ? 0.35 + 0.65 * (1 - t) : 0.6,
                      ),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

