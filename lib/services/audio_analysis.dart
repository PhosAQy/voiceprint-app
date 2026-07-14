import 'dart:math';
import 'dart:typed_data';

import 'fft.dart';
import 'pitch_detector.dart';
import 'wav_reader.dart';

/// 音频分析结果
class AudioAnalysisResult {
  final List<double> waveform; // 14 个采样点，用于缩略图
  final List<double> overviewWaveform; // 60 个采样点，用于详情页概览
  final List<List<double>> resonanceStack; // 20 段，每段 [胸腔, 鼻腔, 头腔, 大白嗓]
  final List<double> pitch; // 20 个音高点，归一化 0.0-1.0 (C3-C5)
  final Duration duration;

  const AudioAnalysisResult({
    required this.waveform,
    required this.overviewWaveform,
    required this.resonanceStack,
    required this.pitch,
    required this.duration,
  });
}

/// 音频分析服务 — 从 WAV 文件提取波形、音高曲线、共鸣比例
class AudioAnalysisService {
  AudioAnalysisService._();

  static const int _segmentCount = 20;
  static const int _thumbnailSamples = 14;
  static const int _overviewSamples = 60;
  static const int _fftSize = 2048;
  static const int _pitchSize = 1024;

  /// 分析 WAV 文件
  static Future<AudioAnalysisResult> analyze(String wavFilePath) async {
    final wav = await WavReader.read(wavFilePath);
    final samples = wav.samples;
    final sampleRate = wav.sampleRate;
    final duration = wav.duration;

    // 1. 提取波形缩略图
    final waveform = _extractWaveform(samples, _thumbnailSamples);
    final overviewWaveform = _extractWaveform(samples, _overviewSamples);

    // 2. 分段分析
    final segmentLength = (samples.length / _segmentCount).floor();
    if (segmentLength < _fftSize) {
      // 音频太短，用 fallback
      return _fallbackResult(duration);
    }

    final detector = PitchDetector(sampleRate: sampleRate);
    final resonanceStack = <List<double>>[];
    final pitchValues = <double>[];

    for (var i = 0; i < _segmentCount; i++) {
      final start = i * segmentLength;
      final end =
          (start + segmentLength).clamp(0, samples.length);

      // 提取本段数据
      final segLen = end - start;
      if (segLen < _fftSize) {
        resonanceStack.add([0.4, 0.2, 0.2, 0.2]);
        pitchValues.add(0.5);
        continue;
      }

      final segment = Float64List.sublistView(samples, start, end);

      // 音高检测 — 取段中间的 _pitchSize 个样本
      final pitchStart = (segLen - _pitchSize) ~/ 2;
      final pitchFrame =
          Float64List.sublistView(segment, pitchStart, pitchStart + _pitchSize);
      final freq = detector.detect(pitchFrame);
      if (freq != null) {
        pitchValues.add(PitchDetector.freqToNormalized(freq));
      } else {
        // 尝试多个位置取平均
        final pitches = <double>[];
        for (var p = 0; p < 3; p++) {
          final ps = (segLen / 4 * (p + 1)).floor() - _pitchSize ~/ 2;
          if (ps >= 0 && ps + _pitchSize <= segLen) {
            final f = detector.detect(
                Float64List.sublistView(segment, ps, ps + _pitchSize));
            if (f != null) pitches.add(f);
          }
        }
        if (pitches.isNotEmpty) {
          final avgFreq =
              pitches.reduce((a, b) => a + b) / pitches.length;
          pitchValues.add(PitchDetector.freqToNormalized(avgFreq));
        } else {
          pitchValues.add(0.5); // 无声段，默认中间值
        }
      }

      // 共鸣分析 — 取段中间的 _fftSize 个样本做 FFT
      final fftStart = (segLen - _fftSize) ~/ 2;
      final fftFrame =
          Float64List.sublistView(segment, fftStart, fftStart + _fftSize);
      final mag = FFT.magnitudeSpectrum(fftFrame);
      resonanceStack.add(_calcResonance(mag, sampleRate));
    }

    return AudioAnalysisResult(
      waveform: waveform,
      overviewWaveform: overviewWaveform,
      resonanceStack: resonanceStack,
      pitch: pitchValues,
      duration: duration,
    );
  }

  /// 从 PCM 采样提取波形（取绝对值最大值归一化）
  static List<double> _extractWaveform(Float64List samples, int count) {
    if (samples.isEmpty) return List.filled(count, 0.1);

    final segmentLength = (samples.length / count).floor();
    if (segmentLength == 0) return List.filled(count, 0.1);

    final result = List<double>.filled(count, 0.0);
    var maxVal = 0.001;

    for (var i = 0; i < count; i++) {
      final start = i * segmentLength;
      final end = (start + segmentLength).clamp(0, samples.length);
      var peak = 0.0;
      for (var j = start; j < end; j++) {
        final abs = samples[j].abs();
        if (abs > peak) peak = abs;
      }
      // 应用一些非线性放大让小信号也可见
      final v = sqrt(peak);
      result[i] = v;
      if (v > maxVal) maxVal = v;
    }

    // 归一化到 0.12 ~ 1.0 范围
    for (var i = 0; i < count; i++) {
      result[i] = (result[i] / maxVal).clamp(0.12, 1.0);
    }
    return result;
  }

  /// 基于 FFT 频段能量计算共鸣比例
  ///
  /// 频段划分（近似，基于声学共鸣特性）：
  /// - 胸腔共鸣: 80–350 Hz (低频，基频和低次谐波)
  /// - 鼻腔共鸣: 350–1500 Hz (中低频)
  /// - 头腔共鸣: 1500–4000 Hz (中高频，"金属感"和"穿透力")
  /// - 大白嗓: 其余 (极高/极低频，无聚焦共鸣)
  static List<double> _calcResonance(
      List<double> magnitude, int sampleRate) {
    final chest = FFT.bandEnergy(magnitude, sampleRate, 80, 350);
    final nasal = FFT.bandEnergy(magnitude, sampleRate, 350, 1500);
    final head = FFT.bandEnergy(magnitude, sampleRate, 1500, 4000);
    // 大白嗓: 总能量减去以上三段
    final total = FFT.bandEnergy(magnitude, sampleRate, 60, 8000);
    final raw = (total - chest - nasal - head).abs();

    final sum = chest + nasal + head + raw;
    if (sum < 1e-10) return [0.4, 0.2, 0.2, 0.2];

    return [
      chest / sum,
      nasal / sum,
      head / sum,
      raw / sum,
    ];
  }

  /// 音频太短时的 fallback
  static AudioAnalysisResult _fallbackResult(Duration duration) {
    final rng = _SeededRng(42);
    return AudioAnalysisResult(
      waveform: List.generate(
          _thumbnailSamples, (_) => 0.3 + rng.nextDouble() * 0.5),
      overviewWaveform: List.generate(
          _overviewSamples, (_) => 0.2 + rng.nextDouble() * 0.6),
      resonanceStack: List.generate(
          _segmentCount, (_) => [0.4, 0.25, 0.2, 0.15]),
      pitch: List.generate(_segmentCount, (_) => 0.5),
      duration: duration,
    );
  }
}

class _SeededRng {
  int _state;
  _SeededRng(int seed) : _state = seed.abs() + 1;

  double nextDouble() {
    _state = (_state * 1103515245 + 12345) & 0x7FFFFFFF;
    return _state / 0x7FFFFFFF;
  }
}
