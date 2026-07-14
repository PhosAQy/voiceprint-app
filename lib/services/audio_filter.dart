import 'dart:math' as math;
import 'dart:typed_data';

/// 基础音频滤波器 — 去除常见杂音
///
/// 包含三个阶段：
/// 1. 高通滤波（80Hz 以下）— 去除电源嗡鸣、空调嗡鸣、桌面震动
/// 2. 低通滤波（8000Hz 以上）— 去除高频白噪、电流声、风噪
/// 3. 软降噪门 — 估算噪声底，对低能量段做衰减（不全静音，避免突变）
class AudioFilter {
  AudioFilter._();

  /// 对采样数据应用全部滤波链，返回过滤后的新数组
  static Float64List process(Float64List samples, int sampleRate) {
    var out = highPass(samples, sampleRate, cutoffHz: 80);
    out = lowPass(out, sampleRate, cutoffHz: 8000);
    out = noiseGate(out, sampleRate);
    return out;
  }

  /// 一阶高通 IIR 滤波器
  /// y[n] = α * (y[n-1] + x[n] - x[n-1])
  /// α = RC / (RC + dt), RC = 1 / (2π * fc), dt = 1 / fs
  static Float64List highPass(
      Float64List samples, int sampleRate, {double cutoffHz = 80}) {
    if (samples.isEmpty) return Float64List(0);
    final dt = 1.0 / sampleRate;
    final rc = 1.0 / (2 * math.pi * cutoffHz);
    final alpha = rc / (rc + dt);

    final out = Float64List(samples.length);
    out[0] = samples[0];
    for (var i = 1; i < samples.length; i++) {
      out[i] = alpha * (out[i - 1] + samples[i] - samples[i - 1]);
    }
    return out;
  }

  /// 一阶低通 IIR 滤波器
  /// y[n] = α * x[n] + (1-α) * y[n-1]
  /// α = dt / (RC + dt)
  static Float64List lowPass(
      Float64List samples, int sampleRate, {double cutoffHz = 8000}) {
    if (samples.isEmpty) return Float64List(0);
    final dt = 1.0 / sampleRate;
    final rc = 1.0 / (2 * math.pi * cutoffHz);
    final alpha = dt / (rc + dt);

    final out = Float64List(samples.length);
    out[0] = samples[0];
    for (var i = 1; i < samples.length; i++) {
      out[i] = alpha * samples[i] + (1 - alpha) * out[i - 1];
    }
    return out;
  }

  /// 软降噪门 — 估算噪声底，对低能量段衰减（不全静音，避免突变）
  ///
  /// 算法：
  /// 1. 按 100ms 窗口扫描，计算每个窗口的 RMS
  /// 2. 取所有窗口 RMS 的 10 分位数作为噪声底估计
  /// 3. 噪声底 ×3 作为门限
  /// 4. 低于门限的窗口：衰减到 20%（不全零，保留背景感）
  /// 5. 门限附近做软过渡（线性渐变），避免咔哒声
  static Float64List noiseGate(Float64List samples, int sampleRate) {
    if (samples.isEmpty) return Float64List(0);

    final winSize = (sampleRate * 0.1).round(); // 100ms 窗口
    if (samples.length < winSize) return Float64List.fromList(samples);

    // 1. 计算每个窗口 RMS
    final winCount = samples.length ~/ winSize;
    final rmsList = <double>[];
    for (var w = 0; w < winCount; w++) {
      final start = w * winSize;
      var sumSq = 0.0;
      for (var i = 0; i < winSize; i++) {
        final s = samples[start + i];
        sumSq += s * s;
      }
      rmsList.add(math.sqrt(sumSq / winSize));
    }

    // 2. 噪声底 = 10 分位 RMS
    final sorted = List<double>.from(rmsList)..sort();
    final noiseFloor = sorted[(sorted.length * 0.1).floor()];
    if (noiseFloor < 1e-6) return Float64List.fromList(samples);

    // 3. 门限 = 噪声底 ×3，软过渡区 = 门限的 0.7~1.0 倍
    final threshold = noiseFloor * 3;
    final softLow = threshold * 0.7;
    final softHigh = threshold;

    final out = Float64List(samples.length);
    for (var w = 0; w < winCount; w++) {
      final start = w * winSize;
      final end = (start + winSize).clamp(0, samples.length);
      final winRms = rmsList[w];

      // 计算本窗口的增益（0.2 ~ 1.0，软过渡）
      double gain;
      if (winRms >= softHigh) {
        gain = 1.0; // 信号足够强，不衰减
      } else if (winRms <= softLow) {
        gain = 0.2; // 噪声底，衰减到 20%
      } else {
        // 软过渡：0.2 ~ 1.0 线性渐变
        final t = (winRms - softLow) / (softHigh - softLow);
        gain = 0.2 + 0.8 * t;
      }

      for (var i = start; i < end; i++) {
        out[i] = samples[i] * gain;
      }
    }

    // 处理尾部剩余样本（不足一个窗口）
    final tailStart = winCount * winSize;
    for (var i = tailStart; i < samples.length; i++) {
      out[i] = samples[i] * 0.2;
    }

    return out;
  }
}
