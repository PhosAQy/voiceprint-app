import 'dart:math';
import 'dart:typed_data';

/// 简洁的 radix-2 Cooley-Tukey FFT 实现
class FFT {
  FFT._();

  /// 对实数信号做 FFT，返回幅度谱（长度 = n/2+1）
  ///
  /// [samples] 长度必须是 2 的幂。如果不是，内部自动截断到最近的 2 的幂。
  static List<double> magnitudeSpectrum(Float64List samples) {
    var n = samples.length;
    // 截断到最近的 2 的幂
    final pow2 = 1 << (log(n) / log(2)).floor();
    if (pow2 != n) {
      n = pow2;
      samples = Float64List.sublistView(samples, 0, n);
    }

    // 应用 Hann 窗
    final windowed = Float64List(n);
    for (var i = 0; i < n; i++) {
      final w = 0.5 - 0.5 * cos(2 * pi * i / (n - 1));
      windowed[i] = samples[i] * w;
    }

    // 转为复数（虚部全 0）
    final real = Float64List.fromList(windowed);
    final imag = Float64List(n);

    _fftInPlace(real, imag);

    // 计算幅度谱（只取前 n/2+1 个频率 bin）
    final halfN = n ~/ 2 + 1;
    final mag = List<double>.filled(halfN, 0.0);
    for (var i = 0; i < halfN; i++) {
      mag[i] = sqrt(real[i] * real[i] + imag[i] * imag[i]);
    }
    return mag;
  }

  /// 原地 radix-2 FFT
  static void _fftInPlace(Float64List real, Float64List imag) {
    final n = real.length;
    if (n <= 1) return;

    // 位反转排列
    var j = 0;
    for (var i = 1; i < n; i++) {
      var bit = n >> 1;
      while (j & bit != 0) {
        j ^= bit;
        bit >>= 1;
      }
      j ^= bit;
      if (i < j) {
        final tr = real[i];
        real[i] = real[j];
        real[j] = tr;
        final ti = imag[i];
        imag[i] = imag[j];
        imag[j] = ti;
      }
    }

    // 蝶形运算
    for (var len = 2; len <= n; len <<= 1) {
      final halfLen = len >> 1;
      final angle = -2 * pi / len;
      final wReal = cos(angle);
      final wImag = sin(angle);
      for (var i = 0; i < n; i += len) {
        var curReal = 1.0;
        var curImag = 0.0;
        for (var k = 0; k < halfLen; k++) {
          final idx1 = i + k;
          final idx2 = i + k + halfLen;
          final tReal = curReal * real[idx2] - curImag * imag[idx2];
          final tImag = curReal * imag[idx2] + curImag * real[idx2];
          real[idx2] = real[idx1] - tReal;
          imag[idx2] = imag[idx1] - tImag;
          real[idx1] += tReal;
          imag[idx1] += tImag;
          // 旋转因子
          final newReal = curReal * wReal - curImag * wImag;
          curImag = curReal * wImag + curImag * wReal;
          curReal = newReal;
        }
      }
    }
  }

  /// 计算指定频段的能量
  static double bandEnergy(
    List<double> magnitude,
    int sampleRate,
    double freqLow,
    double freqHigh,
  ) {
    final n = (magnitude.length - 1) * 2;
    final binLow = (freqLow / sampleRate * n).floor().clamp(0, magnitude.length - 1);
    final binHigh =
        (freqHigh / sampleRate * n).ceil().clamp(0, magnitude.length - 1);
    var sum = 0.0;
    for (var i = binLow; i <= binHigh && i < magnitude.length; i++) {
      sum += magnitude[i] * magnitude[i];
    }
    return sum;
  }
}
