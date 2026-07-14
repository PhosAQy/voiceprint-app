import 'package:flutter/services.dart';

/// 实时耳返服务 — 调用原生 AudioRecord + AudioTrack 管道
///
/// 原理：Android 原生 AudioRecord(VOICE_COMMUNICATION) → AudioTrack(VOICE_CALL)
/// 延迟约 20-40ms，达到 KTV 级实时监听效果
class EarMonitorService {
  static const _channel = MethodChannel('voiceprint/ear_monitor');

  bool _running = false;

  bool get isRunning => _running;

  /// 开始实时监听
  /// 返回 true 表示成功启动，false 表示无权限或启动失败
  Future<bool> start() async {
    if (_running) return true;
    try {
      final result = await _channel.invokeMethod<bool>('start');
      _running = result ?? false;
      return _running;
    } catch (e) {
      return false;
    }
  }

  /// 停止实时监听
  Future<void> stop() async {
    if (!_running) return;
    try {
      await _channel.invokeMethod<bool>('stop');
    } catch (_) {}
    _running = false;
  }

  Future<void> dispose() async {
    await stop();
  }
}
