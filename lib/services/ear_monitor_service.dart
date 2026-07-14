import 'package:flutter/services.dart';

/// 实时耳返服务 — 调用原生 AudioRecord + AudioTrack + DSP 管道
///
/// 原理：Android 原生 AudioRecord(VOICE_COMMUNICATION, LOW_LATENCY)
///       → Schroeder 混响 + biquad EQ + 麦克风模拟 → AudioTrack(LOW_LATENCY)
/// 延迟约 3-10ms（128 样本缓冲），DSP 全部在原生层实时处理
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

  /// 实时更新 DSP 参数（混响/EQ/音量/麦克风）
  /// 在耳返运行时调用，参数立即生效
  Future<void> updateParams(EarMonitorParams params) async {
    if (!_running) return;
    try {
      await _channel.invokeMethod<bool>('updateParams', {
        'params': params.toMap(),
      });
    } catch (_) {}
  }

  Future<void> dispose() async {
    await stop();
  }
}

/// 耳返 DSP 参数
class EarMonitorParams {
  final int reverbIndex;   // 0=原声 1=录音室 2=大厅 3=KTV 4=演唱会
  final double dryWet;     // 0=纯干声 1=纯湿声
  final double decay;      // 0-1 反馈强度
  final double preDelay;   // 0-1 → 0-60ms
  final double monitorVol; // 0-1
  final double eqLow;      // 0-1, 0.5=0dB
  final double eqMid;
  final double eqHigh;
  final int micIndex;      // 0=动圈 1=电容 2=屏幕麦

  const EarMonitorParams({
    this.reverbIndex = 1,
    this.dryWet = 0.30,
    this.decay = 0.40,
    this.preDelay = 0.33,
    this.monitorVol = 0.75,
    this.eqLow = 0.58,
    this.eqMid = 0.50,
    this.eqHigh = 0.42,
    this.micIndex = 1,
  });

  Map<String, dynamic> toMap() => {
        'reverbIndex': reverbIndex,
        'dryWet': dryWet,
        'decay': decay,
        'preDelay': preDelay,
        'monitorVol': monitorVol,
        'eqLow': eqLow,
        'eqMid': eqMid,
        'eqHigh': eqHigh,
        'micIndex': micIndex,
      };
}
