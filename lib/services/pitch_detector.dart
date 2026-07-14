import 'dart:math';
import 'dart:typed_data';

/// YIN 音高检测算法
///
/// 参考: de Cheveigné & Kawahara (2002) "YIN, a fundamental frequency
/// estimator for speech and music".
class PitchDetector {
  final int sampleRate;
  final double threshold; // 典型 0.10–0.15

  PitchDetector({
    required this.sampleRate,
    this.threshold = 0.12,
  });

  /// 检测一帧信号的基频，返回频率 (Hz)，无声/检测失败返回 null
  double? detect(Float64List buffer) {
    final tauMax = (buffer.length / 2).floor();
    if (tauMax < 2) return null;

    // 1. 差分函数
    final diff = Float64List(tauMax);
    for (var tau = 0; tau < tauMax; tau++) {
      var sum = 0.0;
      for (var i = 0; i < tauMax; i++) {
        final d = buffer[i] - buffer[i + tau];
        sum += d * d;
      }
      diff[tau] = sum;
    }

    // 2. 累积均值归一差分
    final cmnd = Float64List(tauMax);
    cmnd[0] = 1.0;
    var runningSum = 0.0;
    for (var tau = 1; tau < tauMax; tau++) {
      runningSum += diff[tau];
      cmnd[tau] = runningSum == 0 ? 1.0 : diff[tau] * tau / runningSum;
    }

    // 3. 绝对阈值
    var tauEstimate = -1;
    for (var tau = 2; tau < tauMax; tau++) {
      if (cmnd[tau] < threshold) {
        // 找到局部最小值
        while (tau + 1 < tauMax && cmnd[tau + 1] < cmnd[tau]) {
          tau++;
        }
        tauEstimate = tau;
        break;
      }
    }

    if (tauEstimate == -1) {
      // 没有找到低于阈值的点，取全局最小值
      var minVal = double.infinity;
      var minTau = -1;
      for (var tau = 2; tau < tauMax; tau++) {
        if (cmnd[tau] < minVal) {
          minVal = cmnd[tau];
          minTau = tau;
        }
      }
      if (minTau == -1 || minVal > 0.5) return null; // 判定为无声
      tauEstimate = minTau;
    }

    // 4. 抛物线插值提高精度
    final betterTau = _parabolicInterpolation(cmnd, tauEstimate);

    // 5. 转换为频率
    final freq = sampleRate / betterTau;

    // 合理的人声范围: 65Hz ~ 1000Hz
    if (freq < 65 || freq > 1000) return null;

    return freq;
  }

  double _parabolicInterpolation(Float64List cmnd, int tau) {
    if (tau <= 0 || tau >= cmnd.length - 1) return tau.toDouble();
    final s0 = cmnd[tau - 1];
    final s1 = cmnd[tau];
    final s2 = cmnd[tau + 1];
    final denom = s0 + s2 - 2 * s1;
    if (denom == 0) return tau.toDouble();
    final shift = 0.5 * (s0 - s2) / denom;
    return tau + shift;
  }

  /// 将频率 (Hz) 转换为 MIDI 音名编号
  static double freqToMidi(double freq) {
    return 69 + 12 * log(freq / 440.0) / log(2);
  }

  /// 将 MIDI 编号转换为音名 (如 C4, A4)
  static String midiToNote(double midi) {
    final noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    final m = midi.round();
    final octave = (m / 12).floor() - 1;
    final note = noteNames[((m % 12) + 12) % 12];
    return '$note$octave';
  }

  /// 将频率归一化到 C3-C5 范围 (0.0=C3, 1.0=C5)
  static double freqToNormalized(double freq) {
    // C3 = 130.81 Hz, C5 = 523.25 Hz
    const c3 = 130.81;
    const c5 = 523.25;
    if (freq <= 0) return 0.0;
    final logF = log(freq);
    final logC3 = log(c3);
    final logC5 = log(c5);
    final normalized = (logF - logC3) / (logC5 - logC3);
    return normalized.clamp(0.0, 1.0);
  }
}
